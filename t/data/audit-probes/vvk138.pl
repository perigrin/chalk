package C; sub new { bless {v => $_[1]}, $_[0] } sub repl { $_[0] = C->new(9) } package main; my $o = C->new(1); $o->repl; print $o->{v}, "\n";
