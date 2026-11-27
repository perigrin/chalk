my $s = "hello world"; my ($w1,$w2) = $s =~ /(\w+) (\w+)/; ($w1,$w2) = ($w2,$w1) if $w1 lt $w2; print "$w1 $w2\n";
