my @a=("ab","ac"); sub t { $a[1] =~ tr/a/z/ } for my $x (@a) { t(); print $x } print "\n";
