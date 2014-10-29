#!/usr/bin/perl -w

# jon 
# 2005

use HTML::SimpleLinkExtor;
use LWP::UserAgent;
use DBI;

use strict;

# globals

my %config;
my $curl_args;
my $more_curl_args;
my $debug = 1;
my @target ;
my $ua = LWP::UserAgent->new;
my @chunks = [];
my $domain;
my $file;
my $response;
my $h;
my $iface;


# subs
#

sub fetch_next;
sub touch;
sub store;

# CONFIG

%config = ( # configuracion general
		version => '0.0.2',
		author => 'jon <jon@gmail.com>',
		dbtype => 'sqlite',
		user => 'jon', 
		pass => 'supersecretpass', 
		db => 'spiderbot.db',
		table => 'urls',
		path => 'websites/',
		log_file => 'spiderbot.log',
		connect_timeout => '60',
		max_total_size => '1073741824',
		max_size => '31457280',
		min_size => '50240',
		max_time => '216000',
		limit_rate => '0',
		retry => '5',
		max_downloads => '0'
	);

$curl_args =	"--connect-timeout " . $config{'connect_timeout'}.
		" --limit-rate " . $config{'limit_rate'}.
		" --location " .
		" --max-filesize " . $config{'max_size'}.
		" --max-time " . $config{'max_time'}.
		" --retry " . $config{'retry'}.
		" --remote-name " ;

print "[".localtime()."] spiderbot start.\n" if $debug;


while(fetch_next)
{
	undef $more_curl_args ;
	$_=$target[1];
	s/http:\/\///;
	@chunks = split('/',$_);		
	$domain = shift(@chunks);
	$file = '';

	if(@chunks)
	{
		$file = pop(@chunks);
	}
	else
	{
		$file = "index.html";
	}

	print "[".localtime()."] target parsed: [$domain] [".join ('/',@chunks)."] [$file]\n" if $debug;

	$response = $ua->head($target[1]);

	if($response->is_success)
	{
		$h=$response->headers;
		push(@target,$h->header('Content-type'),$h->header('Content-Length'));
		print "[".localtime()."] success getting headers from $domain.\n" if $debug;
	}
	else
	{
		$ua->default_header('Referer' => "http://$domain/img.php");
		
		$response = $ua->head($target[1]);

		if($response->is_success)
		{
			$h=$response->headers;
			push(@target,$h->header('Content-type'),$h->header('Content-Length'));
			print "[".localtime()."] workaround for $domain!.\n" if $debug;
			print "[".localtime()."] success getting headers from $domain.\n" if $debug;
			$more_curl_args = " --referer http://$domain/img.php ";
		}
		else
		{
			print "[".localtime()."] fail getting headers from $target[1].\n";
			touch(1);
			next;
		}


	}

	print "[".localtime()."] found target type $target[6].\n";

	if($target[6] and $target[6]=~/image/)
	{
		if($target[7] and $target[7]<$config{min_size})
		{
			print "[".localtime()."] file $file too small.\n" if $debug;
			touch(2);
			next;
		}

		if($target[7] and $target[7]>$config{max_size})
		{
			print "[".localtime()."] file $file too big.\n" if $debug;
			touch(3);
			next;
		}

		chdir($config{path});
		
		if(not -d $domain)
		{
			mkdir($domain);
			print "[".localtime()."] dir $domain created.\n" if $debug;
		}

		chdir($domain);
		
		foreach my $dir(@chunks)
		{
			if(not -d $dir)
			{
				mkdir($dir);
				print "[".localtime()."] dir $dir created.\n" if $debug;
			}
			chdir($dir);
		}
	
		if(-f $file)
		{
			print "[".localtime()."] $file already download.\n" if $debug;
			touch(9);
			next;

		}
	
		if(system("curl $curl_args $more_curl_args --url $target[1]") == 0)
		{
			print "[".localtime()."] success getting $file.\n" if $debug;
			touch(4);
			next;
		
		}
		else
		{
			print "[".localtime()."] error getting $file, Curl says $?\n";
			touch(5);
			next;
		}

	}


	if($target[6] and $target[3] and $target[3] > 0 and $target[6]=~/html/)
	{
		$response = $ua->get($target[1]);
		
		if($response->is_success)
		{
			my $extractor = HTML::SimpleLinkExtor->new($target[1]);
			$extractor->parse($response->content);
			my @links = $extractor->links;

			--$target[3];
			
			store(\@links);
			touch(6);
			next;

		}
		else
		{
			print "[".localtime()."] failed getting headers from $target[1]\n";
			touch(7);
			next;
		}



	}

	touch(8);

}


exit 0;

sub db_ini
{
	$iface = DBI->connect('DBI:SQLite:dbname='.$config{db}, "", "", {RaiseError => 1}) or die "cant connect to db:$DBI::errstr";
}

sub db_end
{
	$iface->disconnect;
}

sub fetch_next
{

	if(not defined $iface)
	{
		db_ini;
	}

	my $query = $iface->prepare('select count(id) from ' . $config{table} . ' where stat=0') or die $iface->errstr;
	$query->execute();
	
	my @rows = $query->fetchrow_array();
	$query->finish;
	
	if(@rows[0] == 0)
	{
		print "[".localtime()."] spiderbot: nothing to do ;)\n" if $debug;
		return 0;
	}


	$query = $iface->prepare('select * from ' . $config{table} . ' where stat=0 limit 1') or die $iface->errstr;
	$query->execute();

	#data 0 -> id 1 -> url -> 2 timestamp 3 -> level 4 -> stat 5 -> referer
	@target = $query->fetchrow_array();
	$query->finish;
	
	print "[".localtime()."] got new target url=$target[1].\n" if $debug;

	return 1;

}

sub touch
{

	if(not defined $iface)
	{
		db_ini;
	}

	my $code = shift;
	my $sql = "update " . $config{'table'}." set stat=$code where id=".$target[0];
	my $query = $iface->prepare($sql);
	$query->execute;
	$query->finish;
	print "[".localtime()."] blessed id=".$target[0]." with $code done.\n" if $debug;

}

sub store
{

	if(not defined $iface)
	{
		db_ini;
	}

	my $reflink = shift; 

	foreach my $link(@$reflink)
	{
		my $sql = "select count(id) from ".$config{'table'}. " where url like '".$link."' limit 1";
		my $query = $iface->prepare($sql);
		$query->execute;
		if($query->rows == 0)
		{
			my $sql = "insert into " . $config{'table'}. " (url,level,stat,referer) values('".$link."',$target[3],0,$target[0])";
			my $query = $iface->prepare($sql);
			$query->execute;
			$query->finish;
			print "[".localtime()."] stored link: $link refered by $target[0].\n" if $debug;
		}
		else
		{
			print "[".localtime()."] skipping link: $link already stored.\n" if $debug;
			$query->finish;
		}
	}

}
