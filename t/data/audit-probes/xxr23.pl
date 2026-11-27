package O; sub new { bless { c => $_[1] }, $_[0] } sub run { $_[0]{c}->() } package main; sub f { my $o = $_[0]; $_[1]->run; "$o$_[0]" } my $x = 1; print f($x, O->new(sub { $x = 5 })), "\n";
