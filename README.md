# li3_statsd

Lithium library for sending statistical data to [statsd](https://github.com/etsy/statsd).

## Installation

Add a submodule to your li3 libraries:

	git submodule add git@github.com:bruensicke/li3_statsd.git libraries/li3_statsd

and activate it in you app (config/bootstrap/libraries.php), of course:

	Libraries::add('li3_statsd');

## Usage

In order to send data to StatsD, you just call the corresponding method statically, like this:

	StatsD::increment('users.login'); // add one login to counter
	StatsD::increment('users.login', 0.1); // use a samplerate of 0.1

You can also set a custom format to pre/append the statistical message, like this:

	// stats will be written with a path like this myapp.development.users.login
	StatsD::format('myapp.{:environment}.{:name}');

You can set the format on Library load, same goes for host, port and timeout. Find a full example (with all default values) below:

	Libraries::add('li3_statsd', array(
		'host' => 'localhost',
		'port' => 8125,
		'timeout' => 2,
		'format' => '{:environment}.{:name}',
	));

To make it easier for you to get started, please have a look at our own [fork of statsd](https://github.com/bruensicke/statsd).

## Credits

* [li3](http://www.lithify.me)
* [statsd](https://github.com/etsy/statsd)
* [statsd fork](https://github.com/bruensicke/statsd)

