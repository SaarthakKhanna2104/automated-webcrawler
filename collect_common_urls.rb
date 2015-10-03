require 'set'
require 'pp'
require 'awesome_print'
require 'open-uri'

load_arr = ["../diskfetcher_plugins/diskfetcher_base_v2.rb","../sdf_utils.rb", "common_utils/url_utils.rb"]
load_arr.each do |lib|
	require File.expand_path(File.dirname(__FILE__)+ "/" + lib)
end
if ENV["SDF_CI_CHECK"] and __FILE__ == $0
        exit 0
end


###################### This class is to collect junk from the domain ##################

class CrawlerJunk
	include UrlUtils
	attr_accessor :common_urls, :already_visited

	def initialize(domain_url)
		@domain_url = domain_url
		@previous_urls = []
		@already_visited = {}
		@common_urls = {}
                @disk_fetcher_object = DiskfetcherBaseV2Plugin.new(args_hash={})	
                crawl_home = SDF::get_crawl_home
                site_dir = "#{crawl_home}/cache/rss_dir"
                FileUtils.mkdir_p(site_dir) if not File.directory?site_dir
                @args_hash = {:site_dir => site_dir}
	end

############### Function to collect the boiler plate URLs ###########################

	def get_common_urls(url,depth,listing_page_url,use_current_path_for_relative_url)
		
		$log.info "\n1. pages_crawled::::::::::::::: #{@already_visited.size}\n"
		$log.info "\n2. depth::::::::::::::::::::::: #{depth}\n"
		$log.info "\n4. Crawling URL:::::::::::::::: #{url}\n"
		
		return if depth == 3

		return if @already_visited.size == 10
		if @already_visited[url] == nil
			@already_visited[url] = true
		else
			return
		end

		page_urls = find_urls_on_page(url,listing_page_url,use_current_path_for_relative_url)
		return if page_urls == nil
		page_urls.each do |page_url|
			break if @already_visited.size == 10
			begin
				get_common_urls(page_url,depth+1,listing_page_url,use_current_path_for_relative_url) if page_url.match(/http(s)?:\/\/[^\/]+/).to_s == @domain_url
			rescue Exception => e
				$log.info "\n#{e.message}\n"
			end
		end
	end
###################### Returns URLs on a page #############################################
    def find_urls_on_page(current_url,listing_page_url,use_current_path_for_relative_url)
        crawl_home = SDF::get_crawl_home
        page_content_hash = @disk_fetcher_object.get_page_content_hash(current_url,@args_hash)
	if page_content_hash == nil
            $log.info "Page Content hash is nil."
            return
        end
	@disk_fetcher_object.save_to_disk(current_url, page_content_hash)
	source = page_content_hash[:page_content]
	dom = @disk_fetcher_object.get_dom_from_page_content_hash(page_content_hash,@args_hash)
        if not dom 
            $log.info " Unable to create dom" 
            return 
        end
        urls_list = []
	dom.xpath('//a/@href').each do |node|  
	    new_url = node.content
            next if not new_url
            new_url = new_url.chomp.strip
            new_url = new_url.gsub("..","") 
            new_url = new_url.gsub("./","/")
            if relative?(new_url)
                new_url = make_absolute(@domain_url,new_url,listing_page_url,use_current_path_for_relative_url)
            end
            if not new_url.match(/\%/)
	        new_url = URI.encode(new_url)
	    end
            if @common_urls[new_url] == nil
                @common_urls[new_url] = 1
            else
                @common_urls[new_url] = @common_urls[new_url] + 1
            end
            urls_list.push(new_url)
	end
	return urls_list
    end
end
