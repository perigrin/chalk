print "1..3\n";

$x = '1';
$y = '0';

$x eq $x && print "ok 1 - comparison with logical and\n";
$y ne $x || print "ok 2 - comparison with logical or\n";
print ($x && $y) || print "ok 3 - mixed boolean operations\n";