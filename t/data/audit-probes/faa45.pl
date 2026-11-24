my %h=(a=>1); sub g { $h{a}=5; 0 } my $v = $h{a} + g(); print "$v\n";
