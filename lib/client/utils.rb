### APIFY_CLIENT_UTILS

require 'json'
require_relative '../shared/utils'

=begin
from http import HTTPStatus
from typing import TYPE_CHECKING, Any, Awaitable, Callable, Dict, List, Optional, Tuple, TypeVar, cast

from apify_shared.utils import is_file_or_bytes, maybe_extract_enum_member_value

if TYPE_CHECKING:
    from ._errors import ApifyApiError

PARSE_DATE_FIELDS_MAX_DEPTH = 3
PARSE_DATE_FIELDS_KEY_SUFFIX = 'At'

T = TypeVar('T')
StopRetryingType = Callable[[], None]
=end

RECORD_NOT_FOUND_EXCEPTION_TYPES = ['record-not-found', 'record-or-token-not-found']

module Apify

module Utils

	def self._to_safe_id id
		# Identificators of resources in the API are either in the format `resource_id` or `username/resource_id`.
		# Since the `/` character has a special meaning in URL paths,
		# we replace it with `~` for proper route parsing on the API, where after parsing the URL it's replaced back to `/`.
		id.gsub('/', '~')
	end


=begin
def _pluck_data(parsed_response: Any) -> Dict:
    if isinstance(parsed_response, dict) and 'data' in parsed_response:
        return cast(Dict, parsed_response['data'])

    raise ValueError('The "data" property is missing in the response.')


def _pluck_data_as_list(parsed_response: Any) -> List:
    if isinstance(parsed_response, dict) and 'data' in parsed_response:
        return cast(List, parsed_response['data'])

    raise ValueError('The "data" property is missing in the response.')


def _retry_with_exp_backoff(
    func: Callable[[StopRetryingType, int], T],
    *,
    max_retries: int = 8,
    backoff_base_millis: int = 500,
    backoff_factor: float = 2,
    random_factor: float = 1,
) -> T:

    random_factor = min(max(0, random_factor), 1)
    backoff_factor = min(max(1, backoff_factor), 10)
    swallow = True

    def stop_retrying() -> None:
        nonlocal swallow
        swallow = False

    for attempt in range(1, max_retries + 1):
        try:
            return func(stop_retrying, attempt)
        except Exception as e:
            if not swallow:
                raise e

        random_sleep_factor = random.uniform(1, 1 + random_factor)
        backoff_base_secs = backoff_base_millis / 1000
        backoff_exp_factor = backoff_factor ** (attempt - 1)

        sleep_time_secs = random_sleep_factor * backoff_base_secs * backoff_exp_factor
        time.sleep(sleep_time_secs)

    return func(stop_retrying, max_retries + 1)


async def _retry_with_exp_backoff_async(
    async_func: Callable[[StopRetryingType, int], Awaitable[T]],
    *,
    max_retries: int = 8,
    backoff_base_millis: int = 500,
    backoff_factor: float = 2,
    random_factor: float = 1,
) -> T:

    random_factor = min(max(0, random_factor), 1)
    backoff_factor = min(max(1, backoff_factor), 10)
    swallow = True

    def stop_retrying() -> None:
        nonlocal swallow
        swallow = False

    for attempt in range(1, max_retries + 1):
        try:
            return await async_func(stop_retrying, attempt)
        except Exception as e:
            if not swallow:
                raise e

        random_sleep_factor = random.uniform(1, 1 + random_factor)
        backoff_base_secs = backoff_base_millis / 1000
        backoff_exp_factor = backoff_factor ** (attempt - 1)

        sleep_time_secs = random_sleep_factor * backoff_base_secs * backoff_exp_factor
        await asyncio.sleep(sleep_time_secs)

    return await async_func(stop_retrying, max_retries + 1)
=end

	def self._catch_not_found_or_throw exc # 'ApifyApiError'					
		is_not_found_status = (exc.status_code == '404') # HTTPStatus.NOT_FOUND
		is_not_found_type 	= RECORD_NOT_FOUND_EXCEPTION_TYPES.include?(exc.type)
		
		raise exc unless (is_not_found_status && is_not_found_type)
		nil
	end

=begin
def _encode_webhook_list_to_base64(webhooks: List[Dict]) -> str:
    """Encode a list of dictionaries representing webhooks to their base64-encoded representation for the API."""
    data = []
    for webhook in webhooks:
        webhook_representation = {
            'eventTypes': [maybe_extract_enum_member_value(event_type) for event_type in webhook['event_types']],
            'requestUrl': webhook['request_url'],
        }
        if 'payload_template' in webhook:
            webhook_representation['payloadTemplate'] = webhook['payload_template']
        data.append(webhook_representation)

    return base64.b64encode(json.dumps(data).encode('utf-8')).decode('ascii')

=end

	def self._encode_key_value_store_record_value value, content_type
		if !content_type
			if is_file_or_bytes value
				content_type = 'application/octet-stream'
			elsif value.class == String
				content_type = 'text/plain; charset=utf-8'
			else
				content_type = 'application/json; charset=utf-8'
			end
		end
		
		if content_type.include?('application/json') && !is_file_or_bytes(value) && (value.class != String)
			#value = json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False, default=str).encode('utf-8')
			value = value.to_json
		end
		
		[ value, content_type ]
	end

end



end