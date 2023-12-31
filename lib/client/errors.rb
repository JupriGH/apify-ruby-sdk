module Apify

	"""Base class for errors specific to the Apify API Client."""
	class ApifyClientError < Exception 
	end


	"""Error specific to requests to the Apify API.

	An `ApifyApiError` is thrown for successful HTTP requests that reach the API,
	but the API responds with an error response. Typically, those are rate limit
	errors and internal errors, which are automatically retried, or validation
	errors, which are thrown immediately, because a correction by the user is needed.
	"""
	class ApifyApiError < ApifyClientError
		attr_accessor :type, :status_code

		"""Create the ApifyApiError instance.

		Args:
			response (httpx.Response): The response to the failed API call
			attempt (int): Which attempt was the request that failed
		"""		
		def initialize response, attempt 			
			@type = nil
			message = "Unexpected error: #{response.body}"
			
			begin
				response_data = JSON.parse response.body
				if response_data.include?('error')
					message = response_data.dig('error', 'message')
					@type 	= response_data.dig('error', 'type')
				end
			#except ValueError:
			#    pass
			rescue #JSON::ParserError
				
			end
			
			super message

			@name 			= 'ApifyApiError'
			@status_code 	= response.code
			@attempt 		= attempt
			#@http_method 	= response.request.method

			# TODO self.client_method
			# TODO self.original_stack
			# TODO self.path
			# TODO self.stack
		end
	end

	"""Error caused by the response body failing to be parsed.

	This error exists for the quite common situation, where only a partial JSON response is received and
	an attempt to parse the JSON throws an error. In most cases this can be resolved by retrying the
	request. We do that by identifying this error in the _HTTPClient.
	"""
=begin
	class InvalidResponseBodyError < ApifyClientError
		"""Create the InvalidResponseBodyError instance.

		Args:
			response: The response which failed to be parsed
		"""
		@ignore_docs
		def __init__(self, response: httpx.Response) -> None:
			super().__init__('Response body could not be parsed')

			self.name = 'InvalidResponseBodyError'
			self.code = 'invalid-response-body'
			self.response = response
	end
=end

=begin
	def _is_retryable_error(e: Exception) -> bool:
		if isinstance(e, (InvalidResponseBodyError, httpx.NetworkError, httpx.TimeoutException, httpx.RemoteProtocolError)):
			return True

		return False
=end

end
