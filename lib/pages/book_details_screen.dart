import 'package:flutter/material.dart';

class BookDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> bookDetails;
  const BookDetailsScreen({super.key, required this.bookDetails});

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            iconTheme: const IconThemeData(color: Colors.blueGrey, size: 30.0, shadows: <Shadow>[
              Shadow(color: Colors.black, blurRadius: 10.0),
            ]),
            expandedHeight: isDesktop ? 500.0 : 250.0,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                                                                                                                                                                                                                                                                                                                                                                      
                  ClipRRect(
                    child: Image.network(
                      bookDetails['cover'],
                      fit: isDesktop ? BoxFit.cover : BoxFit.fill,
                      color: Colors.black.withOpacity(0.5),
                      colorBlendMode:BlendMode.darken,
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.black,
                          Colors.transparent,
                        ]
                      ),
                    ),
                  ), 
                  Positioned(
                    top: 16.0,
                    left: 16.0,
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          bookDetails['cover']!,
                          width: isDesktop ? 200 : 100,
                          height: isDesktop ? 300 : 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  ),
                  if (isDesktop) Positioned(
                    top: 16.0,
                    right: 16.0,
                    child: SizedBox(
                      width: 300,
                      child: SingleChildScrollView(
                        child: Text(
                          bookDetails['description'] ?? 'No description Available',
                          style: const TextStyle(
                            fontSize: 16.0,
                            color: Colors.white
                          ),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                if (index == 0) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (isDesktop) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      bookDetails['title']!,
                                      style: const TextStyle(
                                        fontSize: 24.0,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey
                                      ),
                                    ),
                                    
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: SizedBox(),
                            )
                          ],
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bookDetails['title']!,
                                style: const TextStyle(
                                  fontSize: 24.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                bookDetails['description'] ?? 'No description available',
                                style: const TextStyle(
                                  fontSize: 16.0,
                                  color: Colors.grey
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  );
                }
                return null;
              },
              childCount: 1,
            )
          )
        ],
      )
    );
  }
}