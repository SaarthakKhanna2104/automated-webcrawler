require 'set'
require 'pp'
require 'httpclient'
require 'nokogiri'
require 'awesome_print'
require 'open-uri'

load_arr = ["../diskfetcher_plugins/diskfetcher_base_v2.rb","../sdf_utils.rb", "common_utils/cluster_2.rb", "collect_common_urls.rb","common_utils/url_utils.rb"]
load_arr.each do |lib|
	require File.expand_path(File.dirname(__FILE__)+ "/" + lib)
end
if ENV["SDF_CI_CHECK"] and __FILE__ == $0
        exit 0
end

class Spider
	include UrlUtils
	attr_accessor :bag_of_words_class_p2, :bag_of_words_node_name, :url_file, :product_url_hash

	def initialize(domain_url)
	    crawl_home = SDF::get_crawl_home
            @disk_fetcher_object = DiskfetcherBaseV2Plugin.new(args_hash={})    
            site_dir = "#{crawl_home}/cache/rss_dir"
            FileUtils.mkdir_p(site_dir) 
            @args_hash = {:site_dir => site_dir}
            @domain_url = domain_url 
	    @bag_of_words_class_p2 = []
            @bag_of_words_node_name = []
            @product_url_hash = {}
	end

        ############ function to create bag of words for the node names for ancestor nodes for <a> ###############
        ############ present on the page #########################################################################
        
	def create_bag_of_words_node_name(dom)
		begin
			grand_parent_node_name = dom.parent.parent.name
		rescue Exception => e
			grand_parent_node_name = nil
		end
		if grand_parent_node_name != "" and grand_parent_node_name
			@bag_of_words_node_name.push(grand_parent_node_name).uniq! 
		end
	end

        ######### function to create bag of words for the ancestor class for <a> ###########
        ####################################################################################
	def create_bag_of_words_class_p(dom)
		begin
			grand_parent_class = dom.parent.parent.attributes['class'].to_s
		rescue Exception => e
			grand_parent_class = nil
		end
		if grand_parent_class != "" and grand_parent_class
			@bag_of_words_class_p2.push(grand_parent_class).uniq! if grand_parent_class
		end
	end

	def get_url_length(url)
		url_array = url.split('/')
		return url_array.size
	end
        
        ###################### reset the parameters for every page #############

        def reset_parameters()
            @product_url_hash = {}
            @bag_of_words_class_p2 = []
            @bag_of_words_node_name = []
        end

        ############## function to vectorise the URL present on page ###########

	def vectorise_input()
		@product_url_hash.each do |url, id|
                    begin
			file_vec = []
			temp_vec_class_p2 = @bag_of_words_class_p2.map do |key|
				id[0].to_s.include?(key)?1:0
			end
			class_p2_index = 0
			temp_vec_class_p2.each_with_index do |e,i|
				class_p2_index += ((i + 1)) if not e.zero?
			end
			node_name_index = 0
			temp_vec_node_name = @bag_of_words_node_name.map do |key|
				id[1].to_s.include?(key)?1:0
			end
			temp_vec_node_name.each_with_index do |e,i|
				node_name_index += (i + 1) if not e.zero?
			end
			#node_depth = id[2]
			url_length = get_url_length(url)
		        @product_url_hash[url] = [class_p2_index**2, node_name_index**4, url_length**4, (class_p2_index * node_name_index)**4]
		    rescue Exception => e
                        $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
                    end
                end
	end

        ################## Creating a URL hash on a page ####################################

	def traverse_xml_tree(dom,depth,page_url,use_current_path_for_relative_url)
		dom.children.each do |node|
			if node.name == "text"
				next
			end
			if node.name == "a" or node.name == "link"
				create_bag_of_words_class_p(node)
				create_bag_of_words_node_name(node)
				begin
					class_p2_name = node.parent.parent.attributes['class'].to_s
					node_name = node.parent.parent.name
                                        node_path = node.path
					href = node.attributes['href'].to_s
					href = href.chomp.strip
					href = href.gsub("..","")
					href = href.gsub("./","/")
                                        #$log.info "HREF: #{href}"
					if relative?(href)
						href = make_absolute(@domain_url,href,page_url,use_current_path_for_relative_url)
                                                #ap href
					end
					if not href.match(/\%/)
						href = URI.encode(href)
					end
                                        #ap product_url_hash
					if href.match(/http(s)?:\/\/[^\/]+/).to_s == @domain_url and @product_url_hash[href] == nil
						node_depth = node.ancestors.size
                                                #puts "INNER_HREF: #{href}"
					        @product_url_hash[href] = [class_p2_name, node_name, node_depth]
                                        end
				rescue Exception => e
					$log.info "\n#{e.message}\n in file #{__FILE__} at line #{__LINE__}"
				end
			end
			traverse_xml_tree(node,depth+1,page_url,use_current_path_for_relative_url)
		end
	end

	def get_dom(current_url)
		page_content_hash = @disk_fetcher_object.get_page_content_hash(current_url,@args_hash)
		return if page_content_hash == nil
		@disk_fetcher_object.save_to_disk(current_url, page_content_hash)
		dom = @disk_fetcher_object.get_dom_from_page_content_hash(page_content_hash,@args_hash)
                if not dom 
                    $log.info " Unable to create dom" 
                    return 
                end
                dom.xpath('//script').remove
                dom.xpath('//style').remove
                dom.xpath('//comment').remove
                return dom
	end
end
