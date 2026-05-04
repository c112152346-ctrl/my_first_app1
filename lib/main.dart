import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() => runApp(const PiggyBankApp());

class PiggyBankApp extends StatelessWidget {
  const PiggyBankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    final String account = _accountController.text.trim();
    final String password = _passwordController.text.trim();

    if (account.isEmpty || password.isEmpty) return;

    setState(() => _isLoading = true);

    // 1. 先去 accounts 節點檢查密碼
    final authUrl = Uri.parse('https://piggybank-a6011-default-rtdb.asia-southeast1.firebasedatabase.app/accounts/$account.json');
    // 2. 準備去 users 節點拿餘額
    final dataUrl = Uri.parse('https://piggybank-a6011-default-rtdb.asia-southeast1.firebasedatabase.app/users/$account.json');

    try {
      final authResponse = await http.get(authUrl);
      final authData = json.decode(authResponse.body);

      // 檢查密碼是否正確
      if (authData != null && authData['pw'].toString() == password) {
        
        // 密碼正確後，抓取該使用者的餘額 (total)
        final dataResponse = await http.get(dataUrl);
        final userData = json.decode(dataResponse.body);
        final int balance = (userData != null) ? (userData['total'] ?? 0) : 0;

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(
              userName: account,
              balance: balance,
            ),
          ),
        );
      } else {
        _showMsg('帳號或密碼錯誤');
      }
    } catch (e) {
      _showMsg('網路連線失敗');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PiggyBank 登入')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_balance_wallet, size: 80, color: Colors.blue),
            const SizedBox(height: 32),
            TextField(controller: _accountController, decoration: const InputDecoration(labelText: '帳號', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _passwordController, decoration: const InputDecoration(labelText: '密碼', border: OutlineInputBorder()), obscureText: true),
            const SizedBox(height: 32),
            _isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(onPressed: _login, child: const Text('登入')),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String userName;
  final int balance;
  const HomePage({super.key, required this.userName, required this.balance});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _amountController = TextEditingController();

  // 建立一個定時抓取「所有使用者」資料的串流
  Stream<Map<String, dynamic>> _allUsersStream() async* {
    while (true) {
      try {
        final url = Uri.parse(
            'https://piggybank-a6011-default-rtdb.asia-southeast1.firebasedatabase.app/users.json');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final Map<String, dynamic> data = json.decode(response.body) ?? {};
          yield data;
        }
      } catch (e) {
        // 抓取失敗
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  // 處理提款邏輯
  Future<void> _processWithdraw(int currentBalance) async {
    final String input = _amountController.text.trim();
    if (input.isEmpty) return;

    final int? withdrawAmount = int.tryParse(input);
    if (withdrawAmount == null || withdrawAmount <= 0) {
      _showMsg('請輸入正確的金額');
      return;
    }

    if (withdrawAmount > currentBalance) {
      _showMsg('餘額不足！');
      return;
    }

    final int newBalance = currentBalance - withdrawAmount;

    try {
      final url = Uri.parse(
          'https://piggybank-a6011-default-rtdb.asia-southeast1.firebasedatabase.app/users/${widget.userName}.json');
      
      final response = await http.patch(
        url,
        body: json.encode({'total': newBalance}),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context);
        _amountController.clear();
        _showMsg('提款成功！正在連線機器給錢...');
      }
    } catch (e) {
      _showMsg('網路連線失敗');
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 建立硬幣顯示元件
  Widget _buildCoinItem(String label, dynamic count) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('\$ $label', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 2),
          Text('${count ?? 0} 個', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
        ],
      ),
    );
  }

  void _showWithdrawDialog(int currentBalance) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('我要提款'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('目前可用餘額：\$ $currentBalance'),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '請輸入提領金額',
                border: OutlineInputBorder(),
                prefixText: '\$ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => _processWithdraw(currentBalance),
            child: const Text('確認提款'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的小豬存錢筒'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _allUsersStream(),
        builder: (context, snapshot) {
          final allData = snapshot.data ?? {};
          
          // 取得目前登入者的餘額
          final int currentBalance = (allData[widget.userName] != null) 
              ? (allData[widget.userName]['total'] ?? 0) 
              : widget.balance;

          // 取得硬幣/鈔票明細
          final Map<String, dynamic> coins = (allData[widget.userName] != null)
              ? (allData[widget.userName]['coins'] ?? {})
              : {};

          // 計算排行榜 (由多到少排序)
          List<MapEntry<String, int>> leaderboard = [];
          allData.forEach((key, value) {
            if (value is Map && value.containsKey('total')) {
              leaderboard.add(MapEntry(key, value['total']));
            }
          });
          leaderboard.sort((a, b) => b.value.compareTo(a.value));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('歡迎回來，${widget.userName}！',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                // 存款卡片
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.blue, Colors.lightBlueAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text('目前存款總額', style: TextStyle(color: Colors.white, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('\$ $currentBalance',
                        style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 提款按鈕
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => _showWithdrawDialog(currentBalance),
                    icon: const Icon(Icons.money_off),
                    label: const Text('我要提款', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // 存款明細
                const Row(
                  children: [
                    Icon(Icons.pie_chart, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('我的存錢筒明細', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.5,
                  children: [
                    _buildCoinItem('1', coins['c1']),
                    _buildCoinItem('5', coins['c5']),
                    _buildCoinItem('10', coins['c10']),
                    _buildCoinItem('50', coins['c50']),
                    _buildCoinItem('100', coins['c100']),
                    _buildCoinItem('500', coins['c500']),
                    _buildCoinItem('1000', coins['c1000']),
                  ],
                ),
                const SizedBox(height: 32),
                // 本週排行榜
                const Row(
                  children: [
                    Icon(Icons.emoji_events, color: Colors.amber),
                    SizedBox(width: 8),
                    Text('本週排行榜', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: leaderboard.length > 5 ? 5 : leaderboard.length, // 顯示前 5 名
                  itemBuilder: (context, index) {
                    final entry = leaderboard[index];
                    final bool isMe = entry.key == widget.userName;
                    
                    // 設定獎牌顏色
                    Color rankColor = Colors.grey.shade400;
                    if (index == 0) rankColor = Colors.amber; // 金
                    if (index == 1) rankColor = Colors.blueGrey.shade300; // 銀
                    if (index == 2) rankColor = Colors.orangeAccent.shade100; // 銅

                    return Card(
                      color: isMe ? Colors.blue.shade50 : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: rankColor,
                          child: Text('${index + 1}', style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(entry.key, 
                          style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal),
                        ),
                        subtitle: isMe ? const Text('這是你') : null,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                const Text('系統狀態', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.sync, color: Colors.blue),
                    title: const Text('實時更新中'),
                    subtitle: Text('最後連線：${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
