my @a=(1..5); my $s=0; while (my $x = shift @a) { last if $x>3; $s+=$x } print "$s @a\n";
