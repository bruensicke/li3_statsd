<?php

namespace li3_statsd\core;

use lithium\core\Environment;
use lithium\analysis\Logger;
use lithium\util\String;

/**
 * Sends statistics to the stats daemon over UDP
 *
 **/
class StatsD extends \lithium\core\StaticObject {

	/**
	 * hostname of remote endpoint
	 *
	 * @var string
	 */
	public static $host = '127.0.0.1';

	/**
	 * port of remote endpoint
	 *
	 * @var integer
	 */
	public static $port = '8125';

	/**
	 * Timeout in seconds before connection attempt is closed
	 *
	 * Two seconds as default is not much, but the point here is, tracking metrics
	 * should not change the behavior of your application, which it would if response
	 * time would be dramatically reduced. This way, we make sure that posting
	 * data is omitted on connection attempts that take way to long.
	 * Under normal conditions every post should be done within this time-limit,
	 * if not, try to investigate why that is the case.
	 *
	 * @var integer
	 */
	public static $timeout = 2;

	/**
	 * messageformat
	 *
	 * @var string
	 */
	public static $format = '{:environment}.{:name}';

	/**
	 * Sets one or more timing values
	 *
	 * @param string|array $stats The metric(s) to set.
	 * @param float $time The elapsed time (ms) to log
	 **/
	public static function timing($stats, $time) {
		StatsD::updateStats($stats, $time, 1, 'ms');
	}

	/**
	 * Sets one or more gauges to a value
	 *
	 * @param string|array $stats The metric(s) to set.
	 * @param float $value The value for the stats.
	 **/
	public static function gauge($stats, $value) {
		StatsD::updateStats($stats, $value, 1, 'g');
	}

	/**
	 * A "Set" is a count of unique events.
	 * This data type acts like a counter, but supports counting
	 * of unique occurences of values between flushes. The backend
	 * receives the number of unique events that happened since
	 * the last flush.
	 *
	 * The reference use case involved tracking the number of active
	 * and logged in users by sending the current userId of a user
	 * with each request with a key of "uniques" (or similar).
	 *
	 * @param string|array $stats The metric(s) to set.
	 * @param float $value The value for the stats.
	 **/
	public static function set($stats, $value) {
		StatsD::updateStats($stats, $value, 1, 's');
	}

	/**
	 * Increments one or more stats counters
	 *
	 * @param string|array $stats The metric(s) to increment.
	 * @param float|1 $sampleRate the rate (0-1) for sampling.
	 * @return boolean
	 **/
	public static function increment($stats, $sampleRate=1) {
		StatsD::updateStats($stats, 1, $sampleRate, 'c');
	}

	/**
	 * Decrements one or more stats counters.
	 *
	 * @param string|array $stats The metric(s) to decrement.
	 * @param float|1 $sampleRate the rate (0-1) for sampling.
	 * @return boolean
	 **/
	public static function decrement($stats, $sampleRate=1) {
		StatsD::updateStats($stats, -1, $sampleRate, 'c');
	}

	/**
	 * Updates one or more stats.
	 *
	 * @param string|array $stats The metric(s) to update. Should be either a string or array of metrics.
	 * @param int|1 $delta The amount to increment/decrement each metric by.
	 * @param float|1 $sampleRate the rate (0-1) for sampling.
	 * @param string|c $metric The metric type ("c" for count, "ms" for timing, "g" for gauge, "s" for set)
	 * @return boolean
	 **/
	public static function updateStats($stats, $delta=1, $sampleRate=1, $metric='c') {
		if (!is_array($stats)) { $stats = array($stats); }
		$data = array();
		foreach($stats as $stat) {
			$data[$stat] = "$delta|$metric";
		}

		StatsD::send($data, $sampleRate);
	}

	/**
	 * sets/gets message format to given $format
	 *
	 * @param string $format new formatmesssage to be used
	 * @return string the parsed string
	 */
	public static function format($format = null) {
		if ($format == null) {
			return static::$format;
		}
		return static::$format = $format;
	}

	/**
	 * sets/gets config
	 *
	 * @param array $config an array with configuration to use
	 * @return void
	 */
	public static function config($config = array()) {
		$valid = array('host', 'port', 'format', 'timeout');
		foreach ($config as $key => $value) {
			if (!in_array($key, $valid)) {
				continue;
			}
			static::$$key = $value;
		}
	}

	/**
	 * returns a replaced version of a generic message format
	 *
	 * used to interpolate names/folders for stats
	 *
	 * @param string $message optional, if given, inserts this as stats name
	 * @return string the parsed string
	 */
	public static function message($message = null) {
		return String::insert(static::$format, array(
			'name' => ($message) ? : '{:name}',
			'environment' => Environment::get(),
		));
	}

	/*
	 * Squirt the metrics over UDP
	 **/
	public static function send($data, $sampleRate=1) {

		// sampling
		$sampledData = array();

		if ($sampleRate < 1) {
			foreach ($data as $stat => $value) {
				if ((mt_rand() / mt_getrandmax()) <= $sampleRate) {
					$sampledData[$stat] = "$value|@$sampleRate";
				}
			}
		} else {
			$sampledData = $data;
		}

		if (empty($sampledData)) {
			return;
		}

		// Wrap this in a try/catch - failures in any of this should be silently ignored
		try {
			$host = static::$host;
			$port = static::$port;
			$fp = fsockopen("udp://$host", $port, $errno, $errstr, static::$timeout);
			if (! $fp) {
				if (!Environment::is('development')) {
					return;
				}
				$msg = sprintf('FAILED to open socket connection to [udp://%s:%s]', $host, $port);
				Logger::error($msg);
				return;
			}
			$message = static::message(); // prepare global params
			foreach ($sampledData as $stat => $value) {
				$stat = str_replace('{:name}', $stat, $message); // finally insert stat into message
				fwrite($fp, "$stat:$value");
				if (Environment::is('development') && !error_get_last()) {
					Logger::debug(sprintf('STATSD: [%s] with value [%s]', $stat, $value));
				}
			}
			fclose($fp);
		} catch (Exception $e) {
			if (Environment::is('development')) {
				$msg = sprintf('li3_stats: FAILED to post data to [udp://%s:%s]', $host, $port);
				Logger::error($msg);
			}
		}
	}
}

?>