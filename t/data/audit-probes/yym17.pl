my %h; @h{qw(a b c)} = (1,2,3); my @k = qw(x y); @h{@k} = (7) x @k; my ($f, @r) = @h{qw(a x y)}; my %inv = reverse %h{qw(a b)}; print join("", map { "$_$h{$_}" } sort keys %h), "$f@r$inv{1}\n";
