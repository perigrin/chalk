my %w=(a=>2,b=>1); my $by=sub { $w{$a} <=> $w{$b} }; my @s=sort $by keys %w; print "@s\n";
