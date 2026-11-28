my %h = (a=>1); my $s = "$h{a} @{[ %h ]} @{[ scalar(keys %h) ]}"; print "$s\n";
