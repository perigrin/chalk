my @a=(1,2,3); my $r=\@a; my @b=@$r; @$r=(); print scalar(@b), scalar(@a),"\n";
