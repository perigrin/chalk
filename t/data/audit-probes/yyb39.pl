my @a=(1,2); sub z { $a[1]+=5 } my $i=0; while ($i < @a) { my $v=$a[$i]; z(); print $v, $a[$i]; $i++ } print "\n";
