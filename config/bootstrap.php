<?php

use lithium\core\Libraries;
use li3_statsd\core\StatsD;

StatsD::config(Libraries::get('li3_statsd'));

?>