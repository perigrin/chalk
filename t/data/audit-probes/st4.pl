package K; sub m { 1 } package main; my $o = {}; my $a = eval { $o->can("m") } ? 1 : 0; bless $o, "K"; my $b = $o->can("m") ? 1 : 0; print "$a$b\n";
