module Apify

	#module Consts
	
	"""Possible Apify storage types."""
	module StorageTypes
		DATASET = 'Dataset'
		KEY_VALUE_STORE = 'Key-value store'
		REQUEST_QUEUE = 'Request queue'
	end

	DEFAULT_API_PARAM_LIMIT = 1000
	REQUEST_ID_LENGTH = 15
	REQUEST_QUEUE_HEAD_MAX_LIMIT = 1000
	EVENT_LISTENERS_TIMEOUT_SECS = 5

	BASE64_REGEXP = '[-A-Za-z0-9+/]*={0,3}'
	ENCRYPTED_INPUT_VALUE_PREFIX = 'ENCRYPTED_VALUE'
	ENCRYPTED_INPUT_VALUE_REGEXP = Regexp.new "^#{ENCRYPTED_INPUT_VALUE_PREFIX}:(#{BASE64_REGEXP}):(#{BASE64_REGEXP})$"
	# 9MB
	MAX_PAYLOAD_SIZE_BYTES = 9437184

=begin
	DEPRECATED_NAMES = [
		'BOOL_ENV_VARS',
		'DATETIME_ENV_VARS',
		'FLOAT_ENV_VARS',
		'INTEGER_ENV_VARS',
		'STRING_ENV_VARS',
		'ActorEventTypes',
		'ActorExitCodes',
		'ApifyEnvVars',
	]


	# The following piece of code is highly inspired by the example in https://peps.python.org/pep-0562.
	# The else branch is missing intentionally! Check the following discussion for details:
	# https://github.com/apify/apify-client-python/pull/132#discussion_r1277294315.
	def __getattr__(name: str) -> Any:
		if name in DEPRECATED_NAMES:
			warnings.warn(
				(
					f'Importing "{name}" from "apify_client.consts" is deprecated and will be removed in the future. '
					'Please use "apify_shared" library instead.'
				),
				category=DeprecationWarning,
				stacklevel=2,
			)
			return globals()[f'_{name}']
		raise AttributeError(f'module {__name__!r} has no attribute {name!r}')
=end
	#end
end
