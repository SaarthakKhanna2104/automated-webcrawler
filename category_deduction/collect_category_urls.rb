require 'set'
require 'pp'
require 'awesome_print'

load_arr = ["../../diskfetcher_plugins/diskfetcher_base_v2.rb","../../sdf_utils.rb","../traverse_page_dom.rb","../common_utils/cluster_2.rb","../common_utils/url_utils.rb"]
load_arr.each do |lib|
	require File.expand_path(File.dirname(__FILE__)+ "/" + lib)
end
if ENV["SDF_CI_CHECK"] and __FILE__ == $0
        exit 0
end

class CollectCategoryUrls
      include UrlUtils
      attr_accessor :bag_of_words_parent_class, :bag_of_words_parent_name

      def initialize(options)
          domain = options[:domain]
          crawl_home = SDF::get_crawl_home
          @disk_fetcher_object = DiskfetcherBaseV2Plugin.new(args_hash={})
          site_dir = "#{crawl_home}/cache/rss_dir"
          FileUtils.mkdir_p(site_dir)
          FileUtils.rm("./automated_webcrawler/url_clusters.txt") if File.exists?("./automated_webcrawler/url_clusters.txt")
          FileUtils.rm("./automated_webcrawler/crawled_urls.txt") if File.exists?("./automated_webcrawler/crawled_urls.txt")
          FileUtils.rm("./automated_webcrawler/computation_info.txt") if File.exists?("./automated_webcrawler/computation_info.txt")
          @f_obj = File.open("./automated_webcrawler/#{domain}_url_clusters.txt","w")
          @p_obj = File.open("./automated_webcrawler/#{domain}_crawled_urls.txt","w")
          @c_obj = File.open("./automated_webcrawler/#{domain}_computation_info.txt","w")
          @args_hash = {:site_dir => site_dir}
          @already_visited = {}
          @bag_of_words_parent_class = []
          @bag_of_words_parent_name = []
      end

      ####### function to collect all the urls from the domain. If the -c option is passed #############
      ####### from the command line args parser, then this function is going to crawl 10 ###############
      ####### random urls and go till depth =2 in the domain, otherwise it will only crawl 1 url #######
      ####### and go till depth = 1.                                                   #################

      def collect_common_urls_hash(url,domain_url,urls_hash,options,depth=0)
          #$log.info "1. Pages crawled: #{@already_visited.size}"
          #$log.info "2. Depth:         #{depth}"
          #$log.info "3. Crawling URL:  #{url}"
          if options[:crawl]
              return if depth == 2 
          else
              return if depth == 1
          end
          return if @already_visited.size == 10
          if @already_visited[url] == nil
              @already_visited[url] = true
          else
              return
          end
          page_urls = find_urls_on_page(url,domain_url,urls_hash)
          return if page_urls == nil
          if options[:crawled_urls]
              @p_obj.puts "URL: #{url} DEPTH: #{depth}"
              $log.info "URLS CRAWLED: #{@already_visited.size}, CRAWLED URL: #{url}"
          end
          page_urls.each do |page_url|
              break if @already_visited.size == 10
              collect_common_urls_hash(page_url,domain_url,urls_hash,options,depth+1) if page_url.match(/http(s)?:\/\/[^\/]+/).to_s == domain_url and not page_url.include?"Redirect"
          end
      end

      ######### The function fetches all the urls which are present on a page ##############
      ######### and stores the ancestor class name and the ancestor tag name of ############
      ######### all the urls (<a>) present on the page. It also simultaneously #############
      ######### creates the bag of words for the ancestor class and the ancestor ###########
      ######### tag name                                                        ############

      def find_urls_on_page(current_url,domain_url,urls_hash)
          dom = get_dom_for_page(current_url)
          if not dom 
              $log.info "Unable to create dom" 
              return 
          end
          urls_list = {}
	  dom.xpath('//a/@href').each do |node|
	      url = node.content
              next if not url 
              create_bag_of_words_for_parent_class(node)
              create_bag_of_words_for_parent_name(node)
              if node.parent.parent.attributes['class']
                  parent_parent_class = node.parent.parent.attributes['class'].to_s
              else
                  parent_parent_class = "UNKNOWN"
              end
              parent_parent_name = node.parent.parent.name
              node_path = node.path
              url = url.chomp.strip
              url = url.gsub("..","") 
              url = url.gsub("./","/")
              if relative?(url)
                  url = make_absolute(domain_url,url)
              end
              if not url.match(/\%/)
	          url = URI.encode(url)
	      end
              next if not url.match(/http(s)?:\/\/[^\/]+/).to_s == domain_url
              urls_list[url] = true if not urls_list[url]
              url_length = get_url_length(url)
              if not urls_hash[url]
                  urls_hash[url] = [1,parent_parent_class,parent_parent_name,url_length,node_path]
              else
                  urls_hash[url][0] += 1
              end
	  end
	  return urls_list.keys
    end

    ######### The function starts the clustering process and if --clusters option is ###########
    ######### passed as an argument, this function will output all the clusters.     ###########

    def get_urls_clusters(vectorised_urls_hash,category_urls_hash,options)
        begin
            kmeans_obj = Kmeans.new
            k = 4
            clusters = kmeans_obj.process(vectorised_urls_hash,category_urls_hash,k)
            if options[:clusters]
                clusters.each_with_index do |cluster,index|
                    $log.info "\n CLUSTER_#{index + 1}\n"
                    $log.info "SIZE: #{cluster.urls_hash.keys.size}"
                    @f_obj.puts "CLUSTER: #{index+1}\n"
                    cluster.urls_hash.each do |url,attr|
                        $log.info "URL: #{url}"
                        @f_obj.puts "URL: #{url} ==> #{attr[0..2]}"
                        #@f_obj.puts "URL: #{url}"
                    end
                end
            end
        rescue Exception => e
            $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
        end
        @f_obj.close
        return clusters
    end
  
    ############# This function is to vectorise the ancestor classes and ancestor tag name ###########
    ############# collected for every url. This is done to create an input for the clustering ########
    ############# algorithm.                                                              ############

    def vectorise_url_attributes(urls_hash)
        urls_hash.each do |url,attributes|
            begin
                url_freq = attributes[0]
                temp_class_vec = @bag_of_words_parent_class.map do |word|
                    attributes[1].include?(word)?1:0
                end
                class_name_index = 0
                temp_class_vec.each_with_index do |e,i|
                    class_name_index += (i+1) if not e.zero?
                end
                node_name_index = 0
                temp_node_name_vec = @bag_of_words_parent_name.map do |word|
                    attributes[2].include?(word)?1:0
                end
                node_name_index = 0
                temp_node_name_vec.each_with_index do |e,i|
                    node_name_index += (i+1) if not e.zero?
                end
                url_length = attributes[3]
                #urls_hash[url] = [url_freq**4,class_name_index**4,node_name_index**2,(class_name_index*node_name_index)**2]
                urls_hash[url] = [class_name_index**4,node_name_index**2,(class_name_index*node_name_index)**2]
                @c_obj.puts "#{url} ==> #{urls_hash[url]}"
            rescue Exception => e
                $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
            end
        end
        @c_obj.puts "====================================================================="
    end

    def create_bag_of_words_for_parent_class(node)
        #parent_class = node.parent.attributes['class'].to_s
        if node.parent.parent.attributes['class']
            parent_parent_class = node.parent.parent.attributes['class'].to_s
        else
            parent_parent_class = "UNKNOWN"
        end
        #ancestor_class = "#{parent_class}_#{parent_parent_class}"
        if parent_parent_class #and parent_class != ""
            @bag_of_words_parent_class.push(parent_parent_class).uniq!
        end
    end

    def create_bag_of_words_for_parent_name(node)
        #parent_name = node.parent.name
        parent_parent_name = node.parent.parent.name
        #ancestor_name = "#{parent_name}_#{parent_parent_name}"
        if parent_parent_name #and parent_name != ""
            @bag_of_words_parent_name.push(parent_parent_name).uniq!
        end
    end

    def get_url_hash_copy(urls_hash,category_urls_hash)
        urls_hash.each do |url,attr|
            #category_urls_hash[url] = attr[1..4]
            category_urls_hash[url] = attr
        end
    end

    ########### This function will remove the urls with occurance frequency less than a ############
    ########### threshold. The function will be called if the -c option is passed as an input ######

    def get_redundant_urls_hash(urls_hash)
        urls_keys = urls_hash.select {|url,value| value[0] < 8}.keys
        urls_keys.each do |key|
            urls_hash.delete(key)
        end
    end

    def get_url_length(url)
        if url
            return url.split('/').size
        else
            return 0
        end
    end

    def get_domain_url(url)
        return url.match(/http(s)?:\/\/[^\/]+/).to_s 
    end

    def put_bag_of_words()
        @c_obj.puts "#### BAG OF WORDS FOR ANCESTOR CLASS ####"
        @c_obj.puts "#{bag_of_words_parent_class}"
        @c_obj.puts "\n\n#### BAG OF WORDS FOR ANCESTOR TAG NAME ####"
        @c_obj.puts "#{bag_of_words_parent_name}"
        @c_obj.puts "=================================================================="
        $log.info "BAG OF WORDS FOR ANCESTOR CLASS: \n#{bag_of_words_parent_class}"
        $log.info "BAG OF WORDS FOR ANCESTOR TAG NAME: \n#{bag_of_words_parent_name}"
    end

    def put_urls_hash(urls_hash)
        @c_obj.puts "URLS HASH"
        urls_hash.each do |url,attr|
            @c_obj.puts "#{url} ==> #{attr[0..2]}"
            $log.info "#{url} ==> #{attr[0..2]}"
        end
        @c_obj.puts "=================================================================="
    end

    def close_file()
        @c_obj.close
    end

    def get_dom_for_page(current_url)
	page_content_hash = @disk_fetcher_object.get_page_content_hash(current_url,@args_hash)
	return if page_content_hash == nil
	@disk_fetcher_object.save_to_disk(current_url,page_content_hash)
	dom = @disk_fetcher_object.get_dom_from_page_content_hash(page_content_hash,@args_hash)
        if not dom 
            return 
        end
        dom.xpath('//script').remove
        dom.xpath('//style').remove
        dom.xpath('//comment').remove
        dom.xpath('//footer').remove
        return dom
    end
end

class CommandLineArgsParser
	def initialize
	end

	def self.validate(options)
		if not options[:url] 
			$log.error "In #{__FILE__} you didn't pass the starting url, can't proceed with the category discovery at line #{__LINE__}"
			return false
                end
		if not options[:domain] 
			$log.error "In #{__FILE__} you didn't pass the domain name for file creation, can't proceed with the category discovery at line #{__LINE__}"
                        return false
		end
		return true
	end

	def self.usage_notes
		script_name=$0
		$stderr.puts <<END
Example :
                ./ruby.sh -l info #{script_name} -u <url> -d <domain_name> #to collect category urls on url <url>
                ./ruby.sh -l info #{script_name} -u <url> -d <domain_name> -c #to collect category urls from <url> and crawl random urls for collecting junk.
                ./ruby.sh -l info #{script_name} -u <url> -d <domain_name> -clusters #to collect category urls from <url> and output the clusters formed.
                ./ruby.sh -l info #{script_name} -u <url> -d <domain_name> -crawled_urls #to collect category urls from <url> and output the random urls crawled.
                ./ruby.sh -l info #{script_name} -u <url> -d <domain_name> -bag_of_words #to collect category urls from <url> and output the bag of words obtained for ancestor class and ancestor tag name.
                ./ruby.sh -l info #{script_name} -u <url> -d <domain_name> -urls_hash #to collect category urls from <url> and output the hash for the urls.
END
	end

	def self.parse(args)
		options = {}
		opts = OptionParser.new do |opts|
			opts.banner = " Usage #{$0} [options] "

			opts.on("-v", "--[no-]verbose","Run Verbosely") do |v|
				options[:verbose] = v
			end
			opts.on("-u","--url URL", String, "url for category discovery") do |v|
				options[:url] = v
			end
                	opts.on("-d","--domain DOMAIN", String, "domain name") do |v|
				options[:domain] = v
			end
                        opts.on("-c","--crawl","do random crawls") do |v|
                                options[:crawl] = v
                        end
                        opts.on("--clusters","output clusters") do |v|
                                options[:clusters] = v
                        end
                        opts.on("--crawled_urls","output random urls crawled for junk collection") do |v|
                                options[:crawled_urls] = v
                        end
                        opts.on("-b","--bag_of_words","output bag of words") do |v|
                                options[:bag_of_words] = v
                        end
                        opts.on("--urls_hash","output hash for the urls") do |v|
                                options[:urls_hash] = v
                        end
                        opts.on("-h","--help","Show this message") do
                                puts opts
                                usage_notes
                                exit (-1)
                        end
	        end
		opts.parse!(args)
		if validate(options)
			return options
		else
			$log.error "#{@log_prefix} Invalid/no args, use -h command for help ",@log_hash 
			exit(-1)
		end
	end 
end

if __FILE__ == $0
    options = CommandLineArgsParser.parse(ARGV)
    url = options[:url]
    c_class_obj = CollectCategoryUrls.new(options)
    urls_hash = {}
    category_urls_hash = {}
    domain_url = c_class_obj.get_domain_url(url)
    c_class_obj.collect_common_urls_hash(url,domain_url,urls_hash,options)
    c_class_obj.put_bag_of_words() if options[:bag_of_words]
    c_class_obj.put_urls_hash(urls_hash) if options[:urls_hash]
    c_class_obj.get_redundant_urls_hash(urls_hash) if options[:crawl]
    c_class_obj.get_url_hash_copy(urls_hash,category_urls_hash)
    c_class_obj.vectorise_url_attributes(urls_hash)
    c_class_obj.close_file()
    c_class_obj.get_urls_clusters(urls_hash,category_urls_hash,options)
end
