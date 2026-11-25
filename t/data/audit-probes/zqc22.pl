my @a=("a","b"); sub z { $a[1]="z" } my $s=""; for my $x (@a) { z(); $s.=$x } print "$s\n";
