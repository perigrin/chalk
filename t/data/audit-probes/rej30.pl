my %h=(a=>{n=>1}); my $x=$h{a}; $h{a}={n=>2}; print "$x->{n}$h{a}{n}\n";
