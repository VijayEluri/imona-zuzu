
# HTTP通信ライブラリ
#         soft.spdv.net

# これはhttpでデータを取得するための簡易ライブラリです。
# gzipの展開、タイムアウト処理をサポートしています。
# mod_perlでの使用時ではホストのダウン状態を保存しておきアクセスを強制遮断することでスロットの無駄使いを減らします。
# 2chとの通信用に作成されたものなので、他のサーバーではうまく動かないかもしれません。

#★使用方法
# require 'http.pl';
# $data = &http'get('http://www.yahoo.co.jp/');

# http://は省略することが出来ます。

#★仕様
# レスポンスヘッダは、@http'headerに格納されますが、こちらも改行は消去されています。

package mhttp;

use Socket;

BEGIN {	#初回起動時のみ
	%downinfo = ();	# ホストダウン情報の初期化
}

##/設定部分/########################

do 'setting.pl';

$ua = 'iMona/1.0';	#USER-AGENT
#$ua = 'Monazilla/1.00 (toolname/ver)';	#USER-AGENT
#$ua = 'Monazilla/1.00 (iMona/1.0)';	#USER-AGENT

$range = 0;		#ダウンロードする範囲を指定する場合(Range: bytes=$range-)

$other = '';	#httpリクエストに任意のデータを追加する場合に使用します。

$method = 'GET';

$http_log = '';#'http_log.txt';	# 通信先のログ(空だと取らない)

####################################


sub get {	#HTTPでデータをダウンロードする。
	$/ = "\x0A";	#改行コードを\x0A(LF)にする。

	@header = ();
	$buffer = '';
	
	$port = 80;

	if($_[0] eq ''){return;}
	$_[0] =~ m/^(http\:\/\/)?([^\/]+)(\/.*)$/;
	
	$host = $2;
	$path = $3;

	if($host =~ m/^([^:]+):([^:]+)$/){
		$host = $1;
		$port = $2;
	}

	if (&checkdown($host) == -1) {
		#warn "downhost was found, host:[$host] downinfo:[$downinfo{$host}]";
		return;
	}

#	if($host eq 'school2.2ch.net'){
#		$ipaddress = "\x40\x47\xB1\xA2";
#	} else {
		$ipaddress = inet_aton("$host");
#	}

	if($ipaddress eq ''){
		&founddown($host);
		warn "ipaddress is NULL, host:[$host] url:[$_[0]]";
		return;
	}

	if($http_log ne ''){
		&print_http_log(time . " $_[0] [${range}-]\n");
	}

	#ポート番号とIPアドレスをセットした構造体を作る。 
	$address = pack_sockaddr_in($port,$ipaddress); 

	$proto = getprotobyname('tcp');
	socket(SOCKET,PF_INET,SOCK_STREAM,$proto);

	# ファイルハンドル SOCKET をバッファリングしない
	select(SOCKET); $|=1; select(STDOUT);
	binmode(SOCKET);

#alarmを使用

	if($windows == 0){
		#perl 5.6のシグナル処理を使用する
		$ENV{PERL_SIGNALS} = "unsafe";
		
		$SIG{'ALRM'} = sub {die "timeout"};	# evalをdie
		alarm($timeout);
	}

	eval{
		connect(SOCKET,$address);

		#print SOCKET "$method $path HTTP/1.1\r\n";
		print SOCKET "$method $path HTTP/1.0\r\n";
		print SOCKET "Host: $host\r\n";
		print SOCKET "User-Agent: $ua\r\n";
		if($range != 0){
			print SOCKET "Range: bytes=${range}-\r\n";
		}
		print SOCKET "Accept: */*\r\n";
		print SOCKET "Accept-Charset: *\r\n";
		print SOCKET "Accept-Language: ja\r\n";
		if($usegzip == 1){
			print SOCKET "Accept-Encoding: gzip\r\n";
		}
		print SOCKET "Connection: close\r\n";
		if($other ne ''){
			print SOCKET $other;
		} else {
			print SOCKET "\r\n";
		}
	};

	if($windows == 0){
		alarm(0);
		if($@ =~ m/timeout/){	#タイムアウトした場合
			&founddown($host);
			return '';
		}
	}

	if($windows == 0){
		$SIG{'ALRM'} = sub {die "timeout2"};	# evalをdie
		if($timeout2 == 0){$timeout2 = $timeout;}
		alarm($timeout2);
	}
	
	eval{
		@line = <SOCKET>;
	};

	if($windows == 0){
		alarm(0);
		if($@ =~ m/timeout/){	#タイムアウトした場合
			return '';
		}
	}

	close (SOCKET);
	
	# バーボンハウス時はアクセスしない
	if (index($line[0], " 403 ") >= 0) {
		&founddown($host);
	} elsif (index($line[0], " 302 ") >= 0) {
		for (@line) {
			if (m%/qb6.2ch.net/_403/%) {
				&founddown($host);
			}
		}
	}

	#@data = ();
	$ishead = 0;
	$gzip = 0;
	$chunked = 0;
	foreach $line (@line) {
		if ($ishead == 0) {
			$line =~ tr/\x0D\x0A//d;

			if ($line eq '') {$ishead = 1; next;}	#ヘッダ部分の読み込み終了

			push(@header, $line);

			if (index($line, ": gzip") >= 0) {$gzip = 1;}	#gzipで圧縮されたデータが送られてきた場合
			if (index($line, "Transfer-Encoding: chunked") >= 0) {
				$chunked = 1;
			}
		} else {
			if($chunked == 1 && $line =~ /^[0-9A-Fa-f]+[ \x0D\x0A]*$/){	#かなり適当な処理
				$buffer =~ s/\x0D\x0A$//;
				next;
			}
			if($_[1] == 0){
				@res = split(/<>/, $line);
				#if($res[0] == 1){$title = $res[5];}
				#if($res[0] < $matist){next;}
				#if($res[0] > $matito){last;}
				if($res[0] != $n){											# 番号が飛んでいるとき
					while ($res[0] != $n) {
						$buffer .= "\x82\xA0\x82\xDA\x81\x5B\x82\xF1<><>???<><>\n";			# あぼーん;
						$n++;
					}
				}
				$line =~ s/^[0-9]+?<>//;
				$line =~ s/(.*?<>.*?<>.*?)<>(.*?)<>/$1<> $2 <>/;
				$n++;
				
			}elsif($_[1] == 1){
				$line =~ s/^[0-9]+?<>([0-9]{10})<>/$1.dat<>/;
				$line =~ s/\(([0-9]+?)\)$/ ($1)/;
				$line =~ s/\r\n/\n/g;
				#chomp $line;
				#$line .= "\n";
			}

			$buffer .= $line;
			#if($gzip == 1){
			#	$buffer .= $line;
			#} else {
			#	$line =~ tr/\x0D\x0A//d;
			#	push(@data, $line);
			#}
		}
	}

	if($gzip == 1){

		#zlibを使用。
		if($unzipmode == 1){
			require Compress::Zlib;
			$buffer = Compress::Zlib::memGunzip($buffer);
			#@data = split(/\n/, $buffer);
		} else {
			$| = 1;

			#ファイルをすでに開いた状態で展開してから閉じるモード
			#しかし$unzipmode = 2の時は、windows+anhttpd環境ではうまく動かなかった。
			#$| = 1にしているにもかかわらず、close(FILE);する前にopen (UNZIP,"gzip -dc $tmpf |");
			#してもファイルの内容がgzipに行っていない模様。

			if (open(FILE, "+< $tmpf")) {	# 展開用に一時ファイルに保存 読み書きモードで開く
			} else {open(FILE, ">$tmpf");}

			binmode(FILE);
			if($win9x == 0){
				flock(FILE, 2);				# ロック確認。ロック
			}
			seek(FILE, 0, 0);			# ファイルポインタを先頭にセット
			$len = length($buffer);
			syswrite(FILE, $buffer, $len);
			truncate(FILE, $len);	# ファイルサイズを書き込んだサイズにする

			if($unzipmode == 3){
				close(FILE);				# closeすれば自動でロック解除
			}

				# 展開
				$buffer = '';
				open (UNZIP,"gzip -dc $tmpf |");
				binmode(UNZIP);
				while(<UNZIP>){
					#$buffer = $_;
					#chomp($buffer);	push(@data, $buffer);
					$buffer .= $_;
				}
				close (UNZIP);

			if($unzipmode == 2){
				close(FILE);				# closeすれば自動でロック解除
			}

			$| = 0;
		}
	}
	
	$buffer;
	$buffer =~ s/(.+?)\n//;

	return $buffer;
	#return @data;
}

# ダウンしているホストが見つかった時、ダウンした時間を設定する。
sub founddown {
	$downinfo{"$_[0]"} = time();
}

# ホストのダウン状態を調べる。
# ダウンを検知してから10分以内は無条件でアクセスを遮断する。
sub checkdown {
	if(time() - $downinfo{"$_[0]"} < 60 * 10) {
		return -1;
	}
	return 0;
}

sub print_http_log {
	if (open( HTTPLOG_RW, ">>$http_log")) {
		if($win9x == 0){
			flock(HTTPLOG_RW, 2);				# ロック確認。ロック
		}
		binmode(HTTPLOG_RW);

		print HTTPLOG_RW $_[0];
		close(HTTPLOG_RW);
	}
}

1;