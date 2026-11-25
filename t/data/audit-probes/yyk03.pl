package C; sub new { bless {n=>$_[1]}, $_[0] } sub DESTROY { print "D$_[0]{n}" } package main; my $o = C->new(1); $o = C->new(2); print "E"; $o = undef; print "\n";
