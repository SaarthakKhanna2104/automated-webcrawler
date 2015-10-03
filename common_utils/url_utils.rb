load_arr = []
load_arr.each do |lib|
	require File.expand_path(File.dirname(__FILE__)+ "/" + lib)
end
if ENV["SDF_CI_CHECK"] and __FILE__ == $0
        exit 0
end

module UrlUtils
    # private :create_absolute_url_from_base, :remove_extra_paths, :create_absolute_url_from_context

    def relative?(url)
        if url
            if url.match(/^http/)
                return false
            else
                return true
            end
        end
        return false
    end

    def make_absolute(potential_base,relative_url,listing_page_url="",use_current_path_for_relative_url=false)
          absolute_url = nil
          begin
              if not relative_url.match(/^\//)
                  if use_current_path_for_relative_url
                      splitted_url_array = listing_page_url.split('/')
                      splitted_url_array[-1] = relative_url
                      absolute_url = splitted_url_array.join('/')
                      return absolute_url
                  else
                      relative_url = '/' + relative_url
                      absolute_url = potential_base + relative_url
                      return absolute_url
                  end
              else 
                  absolute_url = potential_base + relative_url
              end
          rescue Exception => e
              $log.info "#{e.message} at line #{__LINE__} in file #{__FILE__}"
          end
          return absolute_url
    end
end


