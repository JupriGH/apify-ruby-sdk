module Apify

	"""Sub-client for manipulating a single request queue."""
	class RequestQueueClient < ResourceClient

		"""Initialize the RequestQueueClient.

		Args:
			client_key (str, optional): A unique identifier of the client accessing the request queue
		"""
		def initialize client_key: nil, **kwargs
			super resource_path: 'request-queues', **kwargs
			@client_key = client_key
		end

		"""Retrieve the request queue.

		https://docs.apify.com/api/v2#/reference/request-queues/queue/get-request-queue

		Returns:
			dict, optional: The retrieved request queue, or None, if it does not exist
		"""		
		def get = _get

		"""Update the request queue with specified fields.

		https://docs.apify.com/api/v2#/reference/request-queues/queue/update-request-queue

		Args:
			name (str, optional): The new name for the request queue

		Returns:
			dict: The updated request queue
		"""
		def update(name: nil, title: nil) =	_update({name: name, title: title})

		"""Delete the request queue.

		https://docs.apify.com/api/v2#/reference/request-queues/queue/delete-request-queue
		"""		
		def delete = _delete

		"""Retrieve a given number of requests from the beginning of the queue.

		https://docs.apify.com/api/v2#/reference/request-queues/queue-head/get-head

		Args:
			limit (int, optional): How many requests to retrieve

		Returns:
			dict: The desired number of requests from the beginning of the queue.
		"""
		def list_head limit: nil
			_http_get 'head', params: _params(limit: limit, clientKey: @client_key), pluck_data: true
		end

		"""Retrieve a given number of unlocked requests from the beginning of the queue and lock them for a given time.

		https://docs.apify.com/api/v2#/reference/request-queues/queue-head-with-locks/get-head-and-lock

		Args:
			lock_secs (int): How long the requests will be locked for, in seconds
			limit (int, optional): How many requests to retrieve


		Returns:
			dict: The desired number of locked requests from the beginning of the queue.
		"""		
		def list_and_lock_head lock_secs: nil, limit: nil
			_http_post 'head/lock', params: _params(lockSecs: lock_secs, limit: limit, clientKey: @client_key), pluck_data: true
		end

		"""Add a request to the queue.

		https://docs.apify.com/api/v2#/reference/request-queues/request-collection/add-request

		Args:
			request (dict): The request to add to the queue
			forefront (bool, optional): Whether to add the request to the head or the end of the queue

		Returns:
			dict: The added request.
		"""
		def add_request request, forefront: nil
			_http_post 'requests', json: request, params: _params(forefront: forefront, clientKey: @client_key), pluck_data: true
		end

		"""Retrieve a request from the queue.

		https://docs.apify.com/api/v2#/reference/request-queues/request/get-request

		Args:
			request_id (str): ID of the request to retrieve

		Returns:
			dict, optional: The retrieved request, or None, if it did not exist.
		"""	
		def get_request request_id
			_http_get "requests/#{request_id}", params: _params, pluck_data: true
			
		rescue ApifyApiError => exc
			Utils::_catch_not_found_or_throw exc
		end

		"""Update a request in the queue.

		https://docs.apify.com/api/v2#/reference/request-queues/request/update-request

		Args:
			request (dict): The updated request
			forefront (bool, optional): Whether to put the updated request in the beginning or the end of the queue

		Returns:
			dict: The updated request
		"""
		def update_request request, forefront: nil			
			request_id = request['id'] # maybe nil ?

			_http_put "requests/#{request_id}", json: request, params: _params(forefront: forefront, clientKey: @client_key), pluck_data: true
		end

		"""Delete a request from the queue.

		https://docs.apify.com/api/v2#/reference/request-queues/request/delete-request

		Args:
			request_id (str): ID of the request to delete.
		"""		
		def delete_request(request_id) 
			_http_del "requests/#{request_id}", params: _params(clientKey: @client_key)
		end

		"""Prolong the lock on a request.

		https://docs.apify.com/api/v2#/reference/request-queues/request-lock/prolong-request-lock

		Args:
			request_id (str): ID of the request to prolong the lock
			forefront (bool, optional): Whether to put the request in the beginning or the end of the queue after lock expires
			lock_secs (int): By how much to prolong the lock, in seconds
		"""
		def prolong_request_lock request_id, forefront: nil, lock_secs: nil
			_http_put "requests/#{request_id}/lock", params: _params(clientKey: @client_key, forefront: forefront, lockSecs: lock_secs), pluck_data: true
		end

		"""Delete the lock on a request.

		https://docs.apify.com/api/v2#/reference/request-queues/request-lock/delete-request-lock

		Args:
			request_id (str): ID of the request to delete the lock
			forefront (bool, optional): Whether to put the request in the beginning or the end of the queue after the lock is deleted
		"""		
		def delete_request_lock request_id, forefront: nil
			request_params = _params clientKey: @client_key, forefront: forefront

			@http_client.call url: _url("requests/#{request_id}/lock"), method: 'DELETE', params: request_params
			nil
		end

		"""Add requests to the queue.

		https://docs.apify.com/api/v2#/reference/request-queues/batch-request-operations/add-requests

		Args:
			requests (List[Dict[str, Any]]): List of the requests to add
			forefront (bool, optional): Whether to add the requests to the head or the end of the queue
		"""
		def batch_add_requests requests, forefront: nil			
			_http_post 'requests/batch', json: requests, params: _params(clientKey: @client_key, forefront: forefront), pluck_data: true
		end

		"""Delete given requests from the queue.

		https://docs.apify.com/api/v2#/reference/request-queues/batch-request-operations/delete-requests

		Args:
			requests (List[Dict[str, Any]]): List of the requests to delete
		"""		
		def batch_delete_requests requests
			_http_del 'requests/batch', json: requests, params: _params(clientKey: @client_key),  pluck_data: true
		end

		"""List requests in the queue.

		https://docs.apify.com/api/v2#/reference/request-queues/request-collection/list-requests

		Args:
			limit (int, optional): How many requests to retrieve
			exclusive_start_id (str, optional): All requests up to this one (including) are skipped from the result
		"""		
		def list_requests limit: nil, exclusive_start_id: nil
			_http_get 'requests', params: _params(limit: limit, exclusive_start_id: exclusive_start_id, clientKey: @client_key), pluck_data: true
		end
	end

	### RequestQueueCollectionClient

	"""Sub-client for manipulating request queues."""
	class RequestQueueCollectionClient < ResourceCollectionClient

		"""Initialize the RequestQueueCollectionClient with the passed arguments."""
		def initialize(**kwargs) = super resource_path: 'request-queues', **kwargs

		"""List the available request queues.

		https://docs.apify.com/api/v2#/reference/request-queues/queue-collection/get-list-of-request-queues

		Args:
			unnamed (bool, optional): Whether to include unnamed request queues in the list
			limit (int, optional): How many request queues to retrieve
			offset (int, optional): What request queue to include as first when retrieving the list
			desc (bool, optional): Whether to sort therequest queues in descending order based on their modification date

		Returns:
			ListPage: The list of available request queues matching the specified filters.
		"""		
		def list unnamed: nil, limit: nil, offset: nil, desc: nil
			_list unnamed: unnamed, limit: limit, offset: offset, desc: desc
		end

		"""Retrieve a named request queue, or create a new one when it doesn't exist.

		https://docs.apify.com/api/v2#/reference/request-queues/queue-collection/create-request-queue

		Args:
			name (str, optional): The name of the request queue to retrieve or create.

		Returns:
			dict: The retrieved or newly-created request queue.
		"""		
		def get_or_create(name: nil) = _get_or_create name: name
	end

end