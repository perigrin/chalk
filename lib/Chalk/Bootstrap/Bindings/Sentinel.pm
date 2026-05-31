# ABOUTME: Sentinel object placed in Bindings during loop entry for lazy Phi creation.
# ABOUTME: Records the Loop node and the pre-loop binding value for on-demand Phi construction.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::Bindings::Sentinel {
    field $loop      :param :reader;
    field $pre_value :param :reader;
}
