package C; our $n=0; sub a { $n++ } sub b { $n+=10 } package main; for my $m (qw(a b a)) { C->$m } print "$C::n\n";
