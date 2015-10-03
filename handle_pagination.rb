# require '/var/lib/gems/1.8/gems/text-1.3.0/lib/text/levenshtein.rb'
require 'awesome_print'

load_arr = []
load_arr.each do |lib|
	require File.expand_path(File.dirname(__FILE__)+ "/" + lib)
end
if ENV["SDF_CI_CHECK"] and __FILE__ == $0
        exit 0
end

class HandlingPagination

#####################  Function to get all the next page URLs from a listing page #################
	def get_pagination_urls(dom,remove_pagination_parameters)
		pagination_urls = {}
		dom.xpath('//*[contains(@*,"pagi") or contains(@*,"next") or contains(@*, "Next") or contains(@*,"pager")]').each do |node|
			begin 
                                next_url = node.attribute('href').to_s
                                ###### Check if the text contains the 'next' term #################
                                ###### If yes, then check if other attributes also contain ########
                                ###### the 'next'or 'pagin' keyword #########################################
                                
                                if next_url.include?"next" or next_url.include?"Next" or next_url.include?"pagi" or next_url.include?"pager"
                                    count = 0
                                    attribute_nodes = node.attribute_nodes
                                    attribute_nodes.each do |attr|
                                        attr = attr.to_s
                                        count += 1 if attr.include?"next" or attr.include?"Next" or attr.include?"pagi" or attr.include?"pager"
                                    end
                                    next if count < 2
                                end
				if node.name != "a" and node.name != "link"
					url_nodes = node.xpath(".//@href")
                                        url_nodes.each do |url_node|
						href = url_node.content if url_node.content
                                                href = modify_pagination_url(href,remove_pagination_parameters) if href
						pagination_urls[href] = true if href and href != ""
					end
				else
					href = node.attributes['href'].to_s
					$log.info "href: #{href}\n"
                                        href = modify_pagination_url(href,remove_pagination_parameters) if href
					pagination_urls[href] = true if href and href != ""
				end
			rescue Exception => e
				$log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
			end
		end
		return pagination_urls.keys
	end

        ################ function to remove unnecessary parameters from the query ################
        ################ part of URL to avoid redundency #########################################
        
        def modify_pagination_url(href,remove_pagination_parameters)
            begin
                query = nil
                url_array = href.split('?')
                if url_array
                    param_hash = {}
                    param_array = url_array.last.split('&')
                    param_array.each do |param|
                        temp_array = param.split('=')
                        param_hash[temp_array[0]] = temp_array[1]
                    end
                    remove_pagination_parameters.each do |key|
                        if param_hash.keys.include?(key)
                            param_hash.delete(key)
                        end
                    end 
                    query = param_hash.map{|k,v| "#{k}=#{v}"}.join('&')
                    query = URI.encode(query) if not query.match(/\%/)
                    url_array[1] = query
                    href = url_array.join('?')
                end
            rescue Exception => e
                $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
            end
            return href
        end
end
