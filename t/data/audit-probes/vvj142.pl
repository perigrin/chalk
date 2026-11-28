my %h = (a=>{n=>1}); my %c = %{$h{a}}; $c{n} = 2; my $r = $h{a}; $r->{n} = 3; print $h{a}{n}, "\n";
