sub mod { my $r = shift; $r->{n}++; $r = { n => 100 }; $r->{n}++ } my $h={n=>1}; my $v = mod($h); print "$h->{n} $v\n";
