my $r = {a=>1,b=>2}; my @v = @{$r}{qw(a b)}; my @w = @$r{qw(b a)}; print "@v|@w\n";
