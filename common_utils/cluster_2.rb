load_arr = []
load_arr.each do |lib|
    require File.expand_path(File.dirname(__FILE__)+ "/" + lib)
end 
if ENV["SDF_CI_CHECK"] and __FILE__ == $0
         exit 0
end

INFINITY = 1.0/0


############## Calculates the distance between two vectors in the n-dimensional space ###################
def dist_to(point_1, point_2)
	sum = 0
	begin
		no_of_dimensions = point_1.size
		(0..no_of_dimensions-1).each do |cord|
			sum += (point_1[cord] - point_2[cord])**2
		end
	rescue Exception => e
		$log.info "\n#{e.message}\n"
	end
	return Math::sqrt(sum)
end

#########################################################################
# centre: is the centre of the cluster
# points: points present in the cluster
# index: index of the cluster
# url_hash: Each URL mapped to its attributes in the n-dimensional space.
########################################################################

class Cluster
	  attr_accessor :center, :points, :index, :urls_hash
	 
	  # Constructor with a starting centerpoint
	  def initialize(center)
	    @center = center
	    @points = []
	    @index = nil
            @urls_hash = {}
	  end
	 
	  #def sort_cluster_hash(cluster_size_hash)
	  #	return Hash[cluster_size_hash.sort_by {|index, count| -count }[0..1]]
	  #end


	  #def get_size()
	  #	return urls.size
	  #end

#################### Recenters the centroid point and removes all of ###########
#################### the associated points #####################################
	  def recenter!
	  	begin
		    length = @center.size
		    sum_array = Array.new(length) { 0 }
		    old_center = @center
		 
#################### Sum up all x1,x2,x3,x4 coords #############################
		    @points.each do |point|
		      	(0..length-1).each do |cord|
		      		sum_array[cord] += point[cord]
		      	end
		    end
		 
		 	sum_array.each_with_index do |ele,index|
		 		sum_array[index] /= @points.length 
		 	end
################### Reset center and return distance moved ######################
		    @center = sum_array
		rescue Exception => e
			$log.info "\n#{e.message}\n"
		end

	    return dist_to(old_center,@center)    
	  end
end

################## Class for K-means clustering #################################
class Kmeans
	def process(url_hash,attr_hash,k,delta = 0.001)
		clusters = []
 
 		#rand_points = [[0], [500], [1000], [1500], [2000], [2500]]
 		#rand_points = [[0,0], [500,500], [1000,1000], [1500.1500], [2000,2000], [2500,2500]]
		rand_points = [[0,0,0], [500,500,500] , [1000,1000,1000], [1500,1500,1500], [2000,2000,2000], [2500,2500,2500]]
	        #rand_points = [[0,0,0,0], [500,500,500,500], [1000,1000,1000,1000], [1500,1500,1500,1500], [2000,2000,2000,2000],[2500,2500,2500,2500]]
	  	
	  	(1..k).each do |point|
	    	index = (url_hash.keys.size * rand).to_i
	    	key = url_hash.keys[index]
	    	rand_point = rand_points[point - 1]
	    	c = Cluster.new(rand_point)
	    	c.index = point
	    	clusters.push c
	  	end
	  	i = 0
	        while true
################## Assign points to clusters #########################################
    		    i = i + 1
    		    index = nil
    	            url_hash.each do |url,point|
      			    min_dist = +INFINITY
      			    min_cluster = nil	
 			    clusters.each_with_index do |cluster,index|
        			    dist = dist_to(point, cluster.center)
        			    if dist < min_dist
          				min_dist = dist
          				min_cluster = cluster
          				index = min_cluster.index
        			    end
        		    end
        		    min_cluster.points.push(point)
                            min_cluster.urls_hash[url] = attr_hash[url]
 		    end
	      
	    	    clusters.each do |cluster|
	      	        dist_moved = cluster.recenter!
	            end
################# Run k-means max 10 times ##########################################
	 	    if i > 10
	 	        return clusters
	 	    end
################# Reset points for the next iteration ###############################
	    	    clusters.each do |cluster|
	      		cluster.points = []
                        cluster.urls_hash = {}
	    	    end
	        end
	end
end
