package O; sub new { bless [1], shift } sub f { my ($s, $v) = @_; $s->[0] = 5; "$v$_[1]" } package main; my $o = O->new; print $o->f($o->[0]), "\n";
