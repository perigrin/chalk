my @a=(1,2); my $e=exists $a[5]?1:0; $a[5]=1; my $f=exists $a[5]?1:0; print "$e$f\n";
