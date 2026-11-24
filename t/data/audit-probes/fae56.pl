my $t=""; sub risky { my $n=shift; die "odd\n" if $n%2; $n } for my $i (1..4) { my $v = eval { risky($i) }; if ($@) { $t.="e" } else { $t.=$v } } print "$t\n";
