my $o={n=>1}; sub g { $o->{n}=5; 0 } my $v = $o->{n} + g(); print "$v\n";
