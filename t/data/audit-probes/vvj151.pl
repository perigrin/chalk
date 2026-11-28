my %h = (a=>1,b=>2); my %inv; push @{$inv{$h{$_} % 2}}, $_ for sort keys %h; print join("|", map { "@{$inv{$_}}" } sort keys %inv), "\n";
