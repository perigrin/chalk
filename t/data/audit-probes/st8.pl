my $x = 5; my $r = \$x; my $a = ref($r); $r = [1]; my $b = ref($r); print "$a $b\n";
