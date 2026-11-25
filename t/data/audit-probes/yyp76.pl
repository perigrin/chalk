my %h=(a=>1); my $r=\$h{a}; %h=(a=>2); $$r=9; print "$h{a}\n";
