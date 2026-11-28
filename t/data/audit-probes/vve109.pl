package O; sub new { bless {v=>1}, shift } sub f { my ($s, $v) = @_; $s->{v} = 5; "$v$_[1]" } package main; my $o = O->new; print $o->f($o->{v}), "\n";
