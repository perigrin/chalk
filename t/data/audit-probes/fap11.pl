package C; sub new { bless {v=>1}, shift } sub repl { my $old=$_[0]; $_[0] = C->new; $_[0]{v}=$old->{v}+1; } package main; my $o=C->new; $o->repl; $o->repl; print $o->{v},"\n";
