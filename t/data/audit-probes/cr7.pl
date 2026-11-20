use Scalar::Util qw(blessed); my @o = ({}, {}); my @was = map { blessed($_) ? 1 : 0 } @o; bless $_, "K" for @o; my @is = map { blessed($_) ? 1 : 0 } @o; print "@was @is\n";
