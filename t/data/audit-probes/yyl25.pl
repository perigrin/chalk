my ($x, $y) = split /,/, "1,2,3"; my @d = split ".", "a.b"; my @e = split /\./, "a.b"; my @f = split "\\.", "a.b"; my @g = split /b/i, "aBc"; print "$x$y", scalar(@d), "@e@f@g\n";
