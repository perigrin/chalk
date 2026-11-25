my %h=(a=>1,b=>2); sub z { $h{b}=7; $h{a}=7 } my $s=0; $s += $_ for map { z(); $_ } values %h; print "$s\n";
