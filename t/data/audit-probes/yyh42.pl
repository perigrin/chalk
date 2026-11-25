my %h = (a=>1,b=>2); my $n = %h; my $k = keys %h; my $v = values %h; my @e = %h; print $n ? "t" : "f", "$k$v", scalar(@e), %h ? "t" : "f", !%h ? "t" : "f", "\n";
