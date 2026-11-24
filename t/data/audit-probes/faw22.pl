my $r={}; my $c=0; $c++ if %$r; $r->{a}=1; $c+=10 if %$r; %$r=(); $c+=100 if !%$r; print "$c\n";
