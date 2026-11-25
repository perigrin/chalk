my @a=(1,2); sub z { $a[1]=7 } my $i=0; while ($i<2) { my $r=\$a[$i]; z(); print $$r; $i++ } print "\n";
