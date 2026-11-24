my %h=(a=>1,b=>2); my %c; @c{keys %h}=values %h; $c{a}=9; print "$h{a}\n";
