my %h; ($h{a},$h{b})=(1,2); my ($a,$b)=@h{qw(a b)}; ($h{a},$h{b})=($b,$a); print "$h{a}$h{b}\n";
