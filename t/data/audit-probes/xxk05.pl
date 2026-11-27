my @a = (1,2); my %h = (k=>3); for my $c (0,1) { ($c ? $a[0] : $h{k}) = "w$c" } print "@a $h{k}\n";
