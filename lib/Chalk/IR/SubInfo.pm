# ABOUTME: Metadata struct for a subroutine declaration.
# ABOUTME: Stores name, params, scope (my/our/package), and the computation graph.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::SubInfo {
    field $name   :param :reader;
    field $params :param :reader = [];
    field $scope  :param :reader = 'package';
    field $graph  :param :reader = undef;
}
