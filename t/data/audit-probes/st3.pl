package K; package main; my $o = {}; my $a = ($o isa K) ? 1 : 0; bless $o, "K"; my $b = ($o isa K) ? 1 : 0; print "$a$b\n";
