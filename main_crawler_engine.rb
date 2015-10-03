require 'set'
require 'pp'
require 'awesome_print'
require 'open-uri'
require 'cgi'


load_arr = ["handle_pagination.rb","../diskfetcher_plugins/diskfetcher_base_v2.rb","../sdf_utils.rb","traverse_page_dom.rb","collect_common_urls.rb","common_utils/cluster_2.rb","common_utils/url_utils.rb"]
load_arr.each do |lib|
	require File.expand_path(File.dirname(__FILE__)+ "/" + lib)
end
if ENV["SDF_CI_CHECK"] and __FILE__ == $0
        exit 0
end


include UrlUtils
class ProductURLClass
        @@junk_hash = {}
        @@sample_attr = []
	attr_accessor :domain_url, :listing_page_url

	def initialize(domain_url,junk_domain,listing_page_url)
		@domain_url = domain_url 
		@junk_domain = junk_domain
		@listing_page_url = listing_page_url
                @manual_pagination_urls = {}
                FileUtils.rm("urls_list.txt") if File.exists?("urls_list.txt")
                #@f_obj = File.open("urls_list.txt","a")
                FileUtils.rm("pagin_urls.txt") if File.exists?("pagin_urls.txt")
                #@p_obj = File.open("pagin_urls.txt","a")
	end

	def get_url_length(url)
            if url
		return url.split('/').size
            else
                return 0
            end
        end

        ############# function returning all the clusters from a lisitng page #############
        def get_url_clusters(product_url_hash,url_hash)
            begin
                kmeans_obj = Kmeans.new
                k = 3
                clusters = kmeans_obj.process(product_url_hash,url_hash,k)
                clusters.each_with_index do |cluster,index|
                    $log.info "\n CLUSTER_#{index + 1}\n"
                    junk_list = @@junk_hash.select {|url,no_of_occurances| no_of_occurances > 3}.keys
                    junk_list.each do |junk_url|
                        cluster.urls_hash.delete(junk_url)
                    end
                    $log.info "SIZE: #{cluster.urls_hash.keys.size}"
                    cluster.urls_hash.each do |url,attr|
                        $log.info "URL: #{url}"
                    end
                end
            rescue Exception => e
                $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
            end
            return clusters
        end 
        
        ############ function returning all the clusters from a lisitng page #############
        def get_url_params(url)
            begin
                query = URI.parse(url).query
                param_hash = CGI.parse(query)
                param_list = param_hash.keys 
            rescue Exception => e
                param_list = []
            end 
            return param_list
        end

        def get_sample_url_attr(url,dom)
            begin
                xpath_string = "//a[contains(@href,'#{url}')]"
                url_nodes = dom.xpath(xpath_string)
                $log.info "URL_NODES #{url_nodes}"
                url_node = url_nodes.first
                @@sample_attr = [url_node.parent.parent.attributes['class'].to_s,url_node.parent.parent.name,url_node.ancestors.size]
            rescue Exception => e
                $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
                @@sample_attr = []
            end
        end

        ######### function returning the cluster containing product URLs ###############

        def get_product_url_cluster(clusters,sample_product_url,dom)
            length = get_url_length(sample_product_url)
	    param_list = get_url_params(sample_product_url)
	    cluster_index = perform_pattern_matching(clusters,length,param_list)
            return cluster_index
        end


	def run_automated_pagination(crawler,sample_product_url,use_current_path_for_relative_url,remove_pagination_parameters)
		pagn_obj = HandlingPagination.new
		pagination_urls = {}
		tentative_pagn_urls = ["#{@listing_page_url}"]
                product_urls = []
                url_hash = {}
		i = 0
		while not tentative_pagn_urls.empty?
			        all_pagn_urls = tentative_pagn_urls
                                tentative_pagn_urls = []
				all_pagn_urls.each do |page_url|
                                    begin    
                                        cluster_index = nil
					page_url = page_url.chomp.strip
					page_url = page_url.gsub("..","")
					page_url = page_url.gsub("./","/")
					$log.info "\nTHIS IS THE PAGIN URL: #{page_url} <------------\n"
					if page_url.match(/^\?/)
						page_url = @listing_page_url.split('?')[0] + page_url
					elsif relative?(page_url)
						page_url = make_absolute(@domain_url,page_url,@listing_page_url,use_current_path_for_relative_url)
					end
					if not page_url.match(/\%/)
						page_url = URI.encode(page_url)
					end
					$log.info "ABSOLUTE URL: #{page_url}\n\n"
                                        if pagination_urls[page_url] == nil
						i = i + 1
						dom = crawler.get_dom(page_url)
						dom = dom.xpath('//body').first if dom
						crawler.traverse_xml_tree(dom,0,page_url,use_current_path_for_relative_url) if dom
					        crawler.product_url_hash.each do |url,attr|
                                                        url_hash[url] = attr 
                                                end
                                                crawler.vectorise_input 
                                                clusters = get_url_clusters(crawler.product_url_hash,url_hash)  
                                                if @@sample_attr.empty?
                                                    @@sample_attr = get_sample_url_attr(sample_product_url,dom)
                                                end
                                                cluster_index = get_product_url_cluster(clusters,sample_product_url,dom)
                                                $log.info "SELECTED CLUSTER: #{cluster_index}"
                                                clusters[cluster_index].urls_hash.each do |url,attr|
                                                    product_urls.push(url)
                                                end
                                                crawler.reset_parameters()
                                                url_hash = {}
                                                pagination_urls[page_url] = true
						bfs_page_urls = pagn_obj.get_pagination_urls(dom,remove_pagination_parameters) if dom
						if dom
						    bfs_page_urls.each do |url|
						        tentative_pagn_urls.push(url)
						    end
						end
					end
                                    rescue Exception => e
                                          $log.info "#{e.message} in #{__FILE__} at line #{__LINE__}"
                                    end
				end
		end
                return product_urls
	end
 
        ######### pattern matching to identify the cluster with the product URLs ############

        def perform_pattern_matching(url_clusters,url_length,url_params)
		max_density = -999
                params = []
                length = []
		product_url_cluster_index = nil
		url_clusters.each_with_index do |cluster,index|
			page_urls_hash = cluster.urls_hash
			score = 0
			matched_items = 0
			page_urls_hash.each do |url,attr|
                          begin
				length = get_url_length(url)
				params = get_url_params(url)
				############   This is the original code for cluster selection  #################
                                #if length.equal? url_length and params == url_params
				#	score += 10
				#	matched_items += 10
				#end
                                ################################################################################
                                if length.equal? url_length
                                    params.each_with_index do |param,index|
                                        if url_params.include? param
                                            score+=(10*(index+1))
                                        end
                                    end
                                    if params == [] and url_params == []
                                        score+=10
                                    end
                                    if @@sample_attr == attr
                                        $log.info "MATCH!!! #{attr}"
                                        score +=40
                                    end
                                end
                          rescue Exception => e
                              $log.info "#{e.message} in file #{__FILE__} at line #{__LINE__}"
                          end
			end
                        url_density = (score**2.to_f/page_urls_hash.keys.size.to_f) if page_urls_hash
                        ####  Earlier estimation of density #######
			#url_density = (score.to_f/page_urls.size.to_f)*(matched_items.to_f) if page_urls
		        $log.info "density: #{url_density}, score: #{score}, matched items: #{matched_items}, size: #{page_urls_hash.keys.size}"
                        if max_density < url_density
				max_density = url_density
				product_url_cluster_index = index
			end
		end
		return product_url_cluster_index
	end
       
        def check_url_structure(url_structure,pagination_url_structure)
            pagination_url_structure.each_with_index do |part,index|
                if part != url_structure[index]
                    return false
                end
            end
            return true
        end

        def get_url_structure(url,use_current_path_for_relative_url)
            url = url.chomp.strip
            url = url.gsub("..","")
            url = url.gsub("./","")
            if url.match(/^\?/)
	        url = @listing_page_url + url
	    elsif relative?(url)
		url = make_absolute(@domain_url,url,@listing_page_url,use_current_path_for_relative_url)
	    end
	    if not url.match(/\%/)
		url = URI.encode(url)
	    end
            begin
                param_hash = {}
                uri = URI.parse(url).query
                param_hash = CGI.parse(uri) if uri
                params = param_hash.keys
                url = url.split('?')[0]
                url_array = url.split('/')
                url_structure = url_array | params
            rescue Exception => e
                $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
            end
            return url_structure
        end

        def get_parent_node_path_for_pagination(crawler,pagination_url)
            begin
                    dom = crawler.get_dom(@listing_page_url)
                    dom = dom.xpath('//body').first if dom
                    xpath_string = "//a[contains(@href,'#{pagination_url}')]"
                    url_nodes = dom.xpath(xpath_string)
                    node_path = url_nodes.first.path  
                    node_path_array = node_path.to_s.split('/')
                    parent_path_array = []
                    parent_node_var = nil
                    parent_index = nil
                    (0..node_path_array.size-1).each do |i|
                        if node_path_array[-1-i] == "a" or node_path_array[-1-i] == "link"
                            parent_node_var = node_path_array[-2-i]
                            parent_index = node_path_array.size - 2 - i
                            break
                        end
                    end
                    sub = parent_node_var.match(/\[.*\]/)
                    parent_node_var = parent_node_var.gsub("#{sub}","")
                    node_path_array[parent_index] = parent_node_var
                    $log.info "PARENT NODE VAR: #{parent_node_var}"
                    (0..parent_index).each do |i|
                        parent_path_array.push(node_path_array[i])
                    end
                    parent_path = parent_path_array.join('/')
                    $log.info "PARENT PATH: #{parent_path}"    
            rescue Exception => e
                    $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
            end
            return parent_path
        end

        def collect_pagination_urls(crawler,pagination_url,use_current_path_for_relative_url)
                parent_path = get_parent_node_path_for_pagination(crawler,pagination_url)
                pagination_url_structure = get_url_structure(pagination_url,use_current_path_for_relative_url)
                pagination_urls_hash = {}
                flag = nil
                listing_urls = ["#{@listing_page_url}"]
                final_pagination_urls = []
                while not listing_urls.empty?
                    temp_urls = listing_urls
                    listing_urls = []
                    temp_urls.each do |temp_url|
                        begin
                            dom = crawler.get_dom(temp_url) 
                            pagination_nodes = dom.xpath(parent_path)
                            pagination_nodes.each do |node|
                                #href = node.xpath('.//@href').to_s.split('?')[0]
                                href = node.xpath('.//@href').to_s
                                next if not href
                                if pagination_urls_hash[href] == nil
                                    pagination_urls_hash[href] = true
                                    href = href.chomp.strip
                                    href = href.gsub("..","")
                                    href = href.gsub("./","")
                                    if href.match(/^\?/)
				        href = @listing_page_url + href
				    elsif relative?(href)
				        href = make_absolute(@domain_url,href,@listing_page_url,use_current_path_for_relative_url)
				    end
				    if not href.match(/\%/)
				        href = URI.encode(href)
				    end
                                    url_structure = get_url_structure(href,use_current_path_for_relative_url)
                                    flag = check_url_structure(url_structure,pagination_url_structure)
                                    $log.info "URL: #{href}"
                                    if flag
                                        $log.info "URL: #{href}"
                                        final_pagination_urls.push(href)
                                        listing_urls.push(href)
                                    end
                                end
                            end
                        rescue Exception => e
                            $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
                        end
                    end
                end
                return final_pagination_urls
        end

	def get_urls_after_manual_pagination(crawler,pagination_url,sample_product_url,use_current_path_for_relative_url)
		pagination_urls = collect_pagination_urls(crawler,pagination_url,use_current_path_for_relative_url)
                product_urls = {}
                url_hash = {}
                pagination_urls.each do |page_url|
			begin
				dom = crawler.get_dom(page_url)
				dom = dom.xpath('//body').first if dom
				crawler.traverse_xml_tree(dom,0,page_url,use_current_path_for_relative_url) if dom
				$log.info "\n #{crawler.bag_of_words_class_p2} \n"
                                crawler.product_url_hash.each do |url,attr|
                                    url_hash[url] = attr 
                                end
                                crawler.vectorise_input
                                clusters = get_url_clusters(crawler.product_url_hash,url_hash)
                                cluster_index = get_product_url_cluster(clusters,sample_product_url)
                                $log.info "SELECTED CLUSTER: #{cluster_index}"
                                #@p_obj.puts "PAGE ===> #{page_url}"
                                clusters[cluster_index].urls.each do |url|
                                    $log.info "URL: #{url}" if product_urls[url] == nil 
                                    #@p_obj.puts "URL: #{url}" if product_urls[url] == nil
                                    product_urls[url] = true if product_urls[url] == nil
                                end
                                crawler.reset_parameters()     
			rescue Exception => e
				$log.info "\n#{e.message}\n"
			end
		end
		return product_urls
	end

	def process(sample_product_url,pagination_url,use_current_path_for_relative_url,remove_pagination_parameters)
		if @@junk_hash.empty?
			junk_collector = CrawlerJunk.new(@domain_url)
			junk_collector.get_common_urls(@junk_domain,0,@listing_page_url,use_current_path_for_relative_url)
			@@junk_hash = junk_collector.common_urls
		end

		crawler = Spider.new(@domain_url)
	        $log.info "#{sample_product_url}"
		if not pagination_url
                        $log.info "No pagination url provided!"
			product_urls = run_automated_pagination(crawler,sample_product_url,use_current_path_for_relative_url,remove_pagination_parameters)
		else
			#pagination_urls = manual_pagination_array
			product_urls = get_urls_after_manual_pagination(crawler,pagination_url,sample_product_url,use_current_path_for_relative_url)
		end
                return product_urls
        end

	def get_domain(listing_page_url)
		domain = listing_page_url.match(/http(s)?:\/\/[^\/]+/).to_s
		return domain
	end

	def start_automated_rss_process(listing_page_url,sample_product_url,pagination_url,use_current_path_for_relative_url,remove_pagination_parameters)
	    product_urls = process(sample_product_url,pagination_url,use_current_path_for_relative_url,remove_pagination_parameters)
	    return product_urls
	end
end

class CommandLineArgsParser
	def initialize
	end

	def self.validate(options)
		return true
	end

	def self.parse(args)
		options = {}
		opts = OptionParser.new do |opts|
			opts.banner = " Usage #{$0} [options] "

			opts.on("-v", "--[no-]verbose","Run Verbosely") do |v|
				options[:verbose] = v
			end

			opts.on("-l","--listing-page-url URL", String, "listing page url") do |url|
				$log.info "#{@log_prefix} url is #{url}"
				options[:listing_url] = url
			end

			opts.on("-s","--sample_product_url URL", String, "A sample product url") do |url|
				$log.info "#{@log_prefix} sample product url is: #{url}"
				options[:sample_url] = url
			end

	        end
		opts.parse!(args)
		if validate(options)
			return options
		else
			$log.error "#{@log_prefix} Invalid/no args, see use -h command for help ",@log_hash 
			exit(-1)
		end
	end 
end


def get_domain(listing_page_url)
	domain = listing_page_url.match(/http(s)?:\/\/[^\/]+/).to_s
	return domain
end


if __FILE__ == $0
	options = CommandLineArgsParser.parse(ARGV)
	listing_page_url = options[:listing_url]
	sample_url = options[:sample_url]
	junk_domain = domain_url = get_domain(listing_page_url)
	p_class_obj = ProductURLClass.new(domain_url,junk_domain,listing_page_url)
	product_urls = p_class_obj.process(sample_url,false)
        #p_class_obj.process(sample_url,false)
	#ap product_urls
	$log.info "done"
end
