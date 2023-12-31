module Apify

	"""Represents a queue of URLs to crawl.

	Can be used for deep crawling of websites where you start with several URLs and then recursively
	follow links to other pages. The data structure supports both breadth-first and depth-first crawling orders.

	Each URL is represented using an instance of the {@apilink Request} class.
	The queue can only contain unique URLs. More precisely, it can only contain request dictionaries
	with distinct `uniqueKey` properties. By default, `uniqueKey` is generated from the URL, but it can also be overridden.
	To add a single URL multiple times to the queue,
	corresponding request dictionary will need to have different `uniqueKey` properties.

	Do not instantiate this class directly, use the `Actor.open_request_queue()` function instead.

	`RequestQueue` stores its data either on local disk or in the Apify cloud,
	depending on whether the `APIFY_LOCAL_STORAGE_DIR` or `APIFY_TOKEN` environment variables are set.

	If the `APIFY_LOCAL_STORAGE_DIR` environment variable is set, the data is stored in
	the local directory in the following files:
	```
	{APIFY_LOCAL_STORAGE_DIR}/request_queues/{QUEUE_ID}/{REQUEST_ID}.json
	```
	Note that `{QUEUE_ID}` is the name or ID of the request queue. The default request queue has ID: `default`,
	unless you override it by setting the `APIFY_DEFAULT_REQUEST_QUEUE_ID` environment variable.
	The `{REQUEST_ID}` is the id of the request.

	If the `APIFY_TOKEN` environment variable is set but `APIFY_LOCAL_STORAGE_DIR` is not, the data is stored in the
	[Apify Request Queue](https://docs.apify.com/storage/request-queue)
	cloud storage.
	"""
	class RequestQueue < BaseStorage

		HUMAN_FRIENDLY_LABEL = StorageTypes::REQUEST_QUEUE

		MAX_CACHED_REQUESTS = 1_000_000

		# When requesting queue head we always fetch requestsInProgressCount * QUERY_HEAD_BUFFER number of requests.
		QUERY_HEAD_MIN_LENGTH = 100

		QUERY_HEAD_BUFFER = 3

		# If queue was modified (request added/updated/deleted) before more than API_PROCESSED_REQUESTS_DELAY_MILLIS
		# then we assume the get head operation to be consistent.
		API_PROCESSED_REQUESTS_DELAY_MILLIS = 10_000
		
		# How many times we try to get queue head with queueModifiedAt older than API_PROCESSED_REQUESTS_DELAY_MILLIS.
		MAX_QUERIES_FOR_CONSISTENCY = 6

		# This number must be large enough so that processing of all these requests cannot be done in
		# a time lower than expected maximum latency of DynamoDB, but low enough not to waste too much memory.
		RECENTLY_HANDLED_CACHE_SIZE = 1000

		# Indicates how long it usually takes for the underlying storage to propagate all writes
		# to be available to subsequent reads.
		STORAGE_CONSISTENCY_DELAY_MILLIS = 3000

		###
		API_PROCESSED_REQUESTS_DELAY = API_PROCESSED_REQUESTS_DELAY_MILLIS / 1000.0 # 10.0 seconds
		STORAGE_CONSISTENCY_DELAY = STORAGE_CONSISTENCY_DELAY_MILLIS / 1000.0 # 3.0 seconds
		
		"""Create a `RequestQueue` instance.

		Do not use the constructor directly, use the `Actor.open_request_queue()` function instead.

		Args:
			id (str): ID of the request queue.
			name (str, optional): Name of the request queue.
			client (ApifyClientAsync or MemoryStorageClient): The storage client which should be used.
			config (Configuration): The configuration which should be used.
		"""
		def initialize id=nil, name: nil, client: nil, config: nil			
			super id, name: name, client: client, config: config

			@_client_key = Crypto._crypto_random_object_id
			@_request_queue_client = client.request_queue @_id, client_key: @_client_key
			
			@_internal_timeout_seconds = 5 * 60

			### ChatGPT: array => they are stored in the order you added them
			# @_queue_head_dict = [] # use array ?
			
			@_queue_head_dict = {} # OrderedDict()			
			@_query_queue_head_task = nil # task
			@_in_progress = Set.new
			@_last_activity = Time.now # datetime.now(timezone.utc)
			@_recently_handled = Utils::LRUCache.new RECENTLY_HANDLED_CACHE_SIZE
			@_requests_cache = Utils::LRUCache.new MAX_CACHED_REQUESTS
			@_assumed_total_count = 0
			@_assumed_handled_count = 0
		end
		
		#def _get_human_friendly_label = 'Request queue'
		
		def self._get_default_id(config) = config.default_request_queue_id
		
		def self._get_single_storage_client(id, client) = client.request_queue id
		
		def self._get_storage_collection_client(client) = client.request_queues
		
		"""Add a request to the queue.

		Args:
			request (dict): The request to add to the queue
			forefront (bool, optional): Whether to add the request to the head or the end of the queue

		Returns:
			dict: Information about the queue operation with keys `requestId`, `uniqueKey`, `wasAlreadyPresent`, `wasAlreadyHandled`.
		"""

		def add_request request, forefront: nil
			Utils::_budget_ow request, ({'url' => [String, true]})
			
			@_last_activity = Time.now # datetime.now(timezone.utc)
			
			# TODO: Check Request class in crawlee and replicate uniqueKey generation logic...
			request['uniqueKey'] ||= normalize_url(request['url'])
			
			cache_key = Utils::_unique_key_to_request_id(request['uniqueKey'])
			cached_info = @_requests_cache.__getitem__(cache_key)

			if cached_info
				request['id'] = cached_info['id']
				return {
					'wasAlreadyPresent' => true,
					# We may assume that if request is in local cache then also the information if the
					# request was already handled is there because just one client should be using one queue.
					'wasAlreadyHandled' => cached_info['isHandled'],
					'requestId'			=> cached_info['id'],
					'uniqueKey' 		=> cached_info['uniqueKey']
				}
			end

			queue_operation_info = @_request_queue_client.add_request(request, forefront: forefront)
			queue_operation_info['uniqueKey'] = request['uniqueKey']

			_cache_request cache_key, queue_operation_info
			
			request_id, was_already_present = queue_operation_info.values_at('requestId', 'wasAlreadyPresent')			 
			
			if	request['handledAt'].nil? &&  #!is_handled
				!was_already_present  && 
				!@_in_progress.include?(request_id) && 
				@_recently_handled[request_id].nil?
			
				@_assumed_total_count += 1
				_maybe_add_request_to_queue_head request_id, forefront
			end

			queue_operation_info
		end

		"""Retrieve a request from the queue.

		Args:
			request_id (str): ID of the request to retrieve.

		Returns:
			dict, optional: The retrieved request, or `None`, if it does not exist.
		"""
		def get_request request_id
			Utils::_budget_ow request_id, [String, true], 'request_id'
			@_request_queue_client.get_request request_id
		end

		"""Return the next request in the queue to be processed.

		Once you successfully finish processing of the request, you need to call
		`RequestQueue.mark_request_as_handled` to mark the request as handled in the queue.
		If there was some error in processing the request, call `RequestQueue.reclaim_request` instead,
		so that the queue will give the request to some other consumer in another call to the `fetch_next_request` method.

		Note that the `None` return value does not mean the queue processing finished, it means there are currently no pending requests.
		To check whether all requests in queue were finished, use `RequestQueue.is_finished` instead.

		Returns:
			dict, optional: The request or `None` if there are no more pending requests.
		"""

		def fetch_next_request
			_ensure_head_is_non_empty

			# We are likely done at this point.
			return if @_queue_head_dict.length == 0
			
			next_request_id, _ = @_queue_head_dict.shift # ~removeFirst()

			# This should never happen, but...
			in_prog = @_in_progress.include?(next_request_id)
			in_hand = @_recently_handled.__getitem__(next_request_id)
			if in_prog || in_hand
				Log.warn 'Queue head returned a request that is already in progress?!', extra: {
					'nextRequestId': next_request_id,
					'inProgress': in_prog,
					'recentlyHandled': !in_prog.nil?,
				}
				return
			end
			
			@_in_progress.add next_request_id
			@_last_activity = Time.now # datetime.now(timezone.utc)
			
			begin
				request = get_request next_request_id				
			rescue Exception => e
				# On error, remove the request from in progress, otherwise it would be there forever
				@_in_progress.delete next_request_id
				raise e
			end
			
			# NOTE: It can happen that the queue head index is inconsistent with the main queue table. This can occur in two situations:

			""" 1) Queue head index is ahead of the main table and the request is not present in the main table yet (i.e. getRequest() returned null).
					In this case, keep the request marked as in progress for a short while,
					so that isFinished() doesn't return true and _ensureHeadIsNonEmpty() doesn't not load the request
					into the queueHeadDict straight again. After the interval expires, fetchNextRequest()
					will try to fetch this request again, until it eventually appears in the main table.
			"""

			if !request
				Log.debug 'Cannot find a request from the beginning of queue, will be retried later', extra: {'nextRequestId': next_request_id}

				Async { # call later, assume we have async loop
					Async::Task.current.sleep STORAGE_CONSISTENCY_DELAY
					@_in_progress.delete next_request_id
				}				
				return
			end
			
			""" 2) Queue head index is behind the main table and the underlying request was already handled
				   (by some other client, since we keep the track of handled requests in recentlyHandled dictionary).
				   We just add the request to the recentlyHandled dictionary so that next call to _ensureHeadIsNonEmpty()
				   will not put the request again to queueHeadDict.
			"""
			
			if request['handledAt']
				Log.debug 'Request fetched from the beginning of queue was already handled', extra: {'nextRequestId': next_request_id}
				@_recently_handled[next_request_id] = true
				return
			end
			
			return request
		end

		"""Mark a request as handled after successful processing.

		Handled requests will never again be returned by the `RequestQueue.fetch_next_request` method.

		Args:
			request (dict): The request to mark as handled.

		Returns:
			dict, optional: Information about the queue operation with keys `requestId`, `uniqueKey`, `wasAlreadyPresent`, `wasAlreadyHandled`.
				`None` if the given request was not in progress.
		"""
		def mark_request_as_handled request
			Utils::_budget_ow request, ({'id' => [String, true], 'uniqueKey' => [String, true], 'handledAt' => [Time, false]})
			
			@_last_activity = Time.now # datetime.now(timezone.utc)

			rid = request['id']
			
			if !@_in_progress.include?(rid)
				Log.debug 'Cannot mark request as handled, because it is not in progress!', extra: {'requestId' => rid}
				return
			end

			request['handledAt'] ||= Time.now # datetime.now(timezone.utc))
			queue_operation_info = @_request_queue_client.update_request({**request})
			queue_operation_info['uniqueKey'] = request['uniqueKey']

			@_in_progress.delete rid
			@_recently_handled[rid] = true

			@_assumed_handled_count += 1 if !queue_operation_info['wasAlreadyHandled']
			
			_cache_request Utils::_unique_key_to_request_id(request['uniqueKey']), queue_operation_info

			queue_operation_info
		end
		
		"""Reclaim a failed request back to the queue.

		The request will be returned for processing later again
		by another call to `RequestQueue.fetchNextRequest`.

		Args:
			request (dict): The request to return to the queue.
			forefront (bool, optional): Whether to add the request to the head or the end of the queue
		Returns:
			dict, optional: Information about the queue operation with keys `requestId`, `uniqueKey`, `wasAlreadyPresent`, `wasAlreadyHandled`.
				`None` if the given request was not in progress.
		"""
		def reclaim_request request, forefront: nil
			Utils::_budget_ow request, ({'id' => [String, true], 'uniqueKey' => [String, true]})
			
			@_last_activity = Time.now # datetime.now(timezone.utc)

			if !@_in_progress.include?(request['id'])
				Log.debug 'Cannot reclaim request, because it is not in progress!', extra: {'requestId': request['id']}
				return
			end
			
			# TODO: If request hasn't been changed since the last getRequest(),
			#       we don't need to call updateRequest() and thus improve performance.
			queue_operation_info = @_request_queue_client.update_request request, forefront: forefront
			queue_operation_info['uniqueKey'] = request['uniqueKey']
			
			_cache_request Utils::_unique_key_to_request_id(request['uniqueKey']), queue_operation_info

			# Wait a little to increase a chance that the next call to fetchNextRequest() will return the request with updated data.
			# This is to compensate for the limitation of DynamoDB, where writes might not be immediately visible to subsequent reads.
			
			Async { |task| # call later, assume we have async loop
				Async::Task.current.sleep STORAGE_CONSISTENCY_DELAY
				# callback
				if  !@_in_progress.include?(request['id'])
					Log.debug 'The request is no longer marked as in progress in the queue?!', extra: {'requestId': request['id']}
					task.stop # return
				end
				
				@_in_progress.delete request['id']

				# Performance optimization: add request straight to head if possible
				_maybe_add_request_to_queue_head request['id'], forefront				
			}

			return queue_operation_info
		end

		def _in_progress_count = @_in_progress.length

		"""Check whether the queue is empty.

		Returns:
			bool: `True` if the next call to `RequestQueue.fetchNextRequest` would return `None`, otherwise `False`.
		"""
		def is_empty
			_ensure_head_is_non_empty
			@_queue_head_dict == 0
		end
		
		"""Check whether the queue is finished.

		Due to the nature of distributed storage used by the queue,
		the function might occasionally return a false negative,
		but it will never return a false positive.

		Returns:
			bool: `True` if all requests were already handled and there are no more left. `False` otherwise.
		"""
		def is_finished
			seconds_since_last_activity = Time.now - @_last_activity
			if (_in_progress_count > 0) && (seconds_since_last_activity > @_internal_timeout_seconds)
				Log.warn "The request queue seems to be stuck for #{@_internal_timeout_seconds}s, resetting internal state."
				_reset
			end

			return false if (@_queue_head_dict.length > 0) || (_in_progress_count > 0)
			# else: both must be == 0
			_ensure_head_is_non_empty true
		end

		def _reset
			@_queue_head_dict.clear
			@_query_queue_head_task = nil
			@_in_progress.clear
			@_recently_handled.clear
			@_assumed_total_count = 0
			@_assumed_handled_count = 0
			@_requests_cache.clear
			@_last_activity = Time.now
		end
		
		def _cache_request cache_key, queue_operation_info
			@_requests_cache.__setitem__ cache_key, {
				'id'				=> queue_operation_info['requestId'],
				'isHandled'			=> queue_operation_info['wasAlreadyHandled'],
				'uniqueKey'			=> queue_operation_info['uniqueKey'],
				'wasAlreadyHandled' => queue_operation_info['wasAlreadyHandled']
			}
		end

		def _queue_query_head limit
			query_started_at = Time.now # datetime.now(timezone.utc)

			list_head = @_request_queue_client.list_head limit: limit			
			items = list_head['items']

			items.each do |request|
				rid = request['id']
				uid = request['uniqueKey']

				# Queue head index might be behind the main table, so ensure we don't recycle requests
				next if (!rid || !uid || @_in_progress.include?(rid) || @_recently_handled.include?(rid)) # @_recently_handled.__getitem__(rid)
				
				@_queue_head_dict[rid] = rid
				_cache_request Utils::_unique_key_to_request_id(uid), {
					'requestId' 		=> rid,
					'wasAlreadyHandled' => false,
					'wasAlreadyPresent' => true,
					'uniqueKey' 		=> uid,
				}
			end
			
			# This is needed so that the next call to _ensureHeadIsNonEmpty() will fetch the queue head again.
			@_query_queue_head_task = nil

			{
				'wasLimitReached'		=> (items.length >= limit),
				'prevLimit' 			=> limit,
				'queueModifiedAt' 		=> Time.iso8601(list_head['queueModifiedAt']),
				'queryStartedAt' 		=> query_started_at,
				'hadMultipleClients' 	=> list_head['hadMultipleClients'],
			}
		end

		def _ensure_head_is_non_empty ensure_consistency: nil, limit: nil, iteration: 0 # iteration: 0
			# If is nonempty resolve immediately.
			return true if @_queue_head_dict.length > 0
			
			limit ||= [_in_progress_count * QUERY_HEAD_BUFFER, QUERY_HEAD_MIN_LENGTH].max
						
			@_query_queue_head_task ||= Async { _queue_query_head limit }
			queue_head = @_query_queue_head_task.wait
			
			# TODO: I feel this code below can be greatly simplified... (comes from TS implementation *wink*)

			""" If queue is still empty then one of the following holds:
			- the other calls waiting for this task already consumed all the returned requests
			- the limit was too low and contained only requests in progress
			- the writes from other clients were not propagated yet
			- the whole queue was processed and we are done
			"""

			# If limit was not reached in the call then there are no more requests to be returned.
			if queue_head['prevLimit'] >= REQUEST_QUEUE_HEAD_MAX_LIMIT
				Log.warn 'Reached the maximum number of requests in progress', extra: {'limit': REQUEST_QUEUE_HEAD_MAX_LIMIT}
			end

			should_repeat_with_higher_limit = 
				(@_queue_head_dict.length == 0) && queue_head['wasLimitReached'] && (queue_head['prevLimit'] < REQUEST_QUEUE_HEAD_MAX_LIMIT)

			# If ensureConsistency=true then we must ensure that either:
			# - queueModifiedAt is older than queryStartedAt by at least API_PROCESSED_REQUESTS_DELAY_MILLIS
			# - hadMultipleClients=false and this.assumedTotalCount<=this.assumedHandledCount
			
			is_database_consistent = (queue_head['queryStartedAt'] - queue_head['queueModifiedAt']) >= API_PROCESSED_REQUESTS_DELAY
			is_locally_consistent = !queue_head['hadMultipleClients'] && (@_assumed_total_count <= @_assumed_handled_count)
			
			# Consistent information from one source is enough to consider request queue finished.
			should_repeat_for_consistency = ensure_consistency && !is_database_consistent && !is_locally_consistent

			# If both are false then head is consistent and we may exit.
			return true if !should_repeat_with_higher_limit && !should_repeat_for_consistency
	
			# If we are querying for consistency then we limit the number of queries to MAX_QUERIES_FOR_CONSISTENCY.
			# If this is reached then we return false so that empty() and finished() returns possibly false negative.
			return false if !should_repeat_with_higher_limit && (iteration > MAX_QUERIES_FOR_CONSISTENCY)
	
			next_limit = should_repeat_with_higher_limit ? (queue_head['prevLimit'] * 1.5).round : queue_head['prevLimit']
			
			# If we are repeating for consistency then wait required time.
			if should_repeat_for_consistency
				delay_seconds = API_PROCESSED_REQUESTS_DELAY - (Time.now - queue_head['queueModifiedAt'])
				Log.info "Waiting for #{delay_seconds}s before considering the queue as finished to ensure that the data is consistent."
				Async::Task.current.sleep delay_seconds
			end

			### repeat
			_ensure_head_is_non_empty ensure_consistency, next_limit, iteration+1
		end
		
		def _maybe_add_request_to_queue_head request_id, forefront
			if forefront				
				# Move to start, i.e. forefront of the queue
				@_queue_head_dict = {request_id => request_id}.merge(@_queue_head_dict) # is this fast ?
			
			elsif @_assumed_total_count < QUERY_HEAD_MIN_LENGTH
				
				# OrderedDict puts the item to the end of the queue by default				
				@_queue_head_dict[request_id] = request_id
			end
		end

		"""Remove the request queue either from the Apify cloud storage or from the local directory."""
		def drop
			@_request_queue_client.delete
			_remove_from_cache
		end
		
		"""Get an object containing general information about the request queue.

		Returns:
			dict: Object returned by calling the GET request queue API endpoint.
		"""
		def get_info = @_request_queue_client.get

		"""Open a request queue.

		Request queue represents a queue of URLs to crawl, which is stored either on local filesystem or in the Apify cloud.
		The queue is used for deep crawling of websites, where you start with several URLs and then
		recursively follow links to other pages. The data structure supports both breadth-first
		and depth-first crawling orders.

		Args:
			id (str, optional): ID of the request queue to be opened.
				If neither `id` nor `name` are provided, the method returns the default request queue associated with the actor run.
				If the request queue with the given ID does not exist, it raises an error.
			name (str, optional): Name of the request queue to be opened.
				If neither `id` nor `name` are provided, the method returns the default request queue associated with the actor run.
				If the request queue with the given name does not exist, it is created.
			force_cloud (bool, optional): If set to True, it will open a request queue on the Apify Platform even when running the actor locally.
				Defaults to False.
			config (Configuration, optional): A `Configuration` instance, uses global configuration if omitted.

		Returns:
			RequestQueue: An instance of the `RequestQueue` class for the given ID or name.
		"""
		def self.open id=nil, name: nil, force_cloud: nil, config: nil
			queue = _open_internal id, name: name, force_cloud: force_cloud, config: config
			queue._ensure_head_is_non_empty
			return queue
		end
	end

end

## TODO: request symbolic JSON keys from http client

def normalize_url url, keep_fragment=nil
	return if url.class != String || url.empty?
	res = URI(url.strip)

	params = nil
	if res.query
		params = URI.encode_www_form URI.decode_www_form(res.query).filter { |x| x[0][0,4] != 'utm_' }.sort_by {|k,v| k}
	end

	proto 	= res.scheme&.downcase||''
	host 	= res.host&.downcase||''
	path 	= res.path&.sub(/\/$/, '')||''
	params 	= params ? "?#{params}" : ''
	hash 	= keep_fragment ? (u.fragment||'') : ''

	"#{proto}://#{host}#{path}#{params}#{hash}"
rescue
	# something wrong: invalid url ?
	url
end
