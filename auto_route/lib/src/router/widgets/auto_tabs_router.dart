import 'package:auto_route/src/router/widgets/auto_tab_view.dart';
import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../auto_route.dart';

typedef AnimatedIndexedStackBuilder = Widget Function(BuildContext context, Widget child, Animation<double> animation);
typedef AutoTabsBuilder = Widget Function(BuildContext context, List<Widget> children, TabsRouter tabsRouter);
typedef AutoTabsPageViewBuilder = Widget Function(BuildContext context, Widget child, PageController pageController);
typedef AutoTabsTabBarBuilder = Widget Function(BuildContext context, Widget child, TabController tabController);
typedef OnNavigationChanged = Function(TabsRouter tabsRouter);

abstract class AutoTabsRouter extends StatefulWidget {
  final List<PageRouteInfo> routes;
  final NavigatorObserversBuilder navigatorObservers;
  final bool inheritNavigatorObservers;

  // if activeIndex != homeIndex
  // set activeIndex to homeIndex
  // else pop parent
  final int homeIndex;

  const AutoTabsRouter._({
    Key? key,
    required this.routes,
    this.homeIndex = -1,
    this.inheritNavigatorObservers = true,
    this.navigatorObservers = AutoRouterDelegate.defaultNavigatorObserversBuilder,
  }) : super(key: key);

  const factory AutoTabsRouter({
    Key? key,
    required List<PageRouteInfo> routes,
    bool lazyLoad,
    Duration duration,
    Curve curve,
    AnimatedIndexedStackBuilder? builder,
    int homeIndex,
    bool inheritNavigatorObservers,
    NavigatorObserversBuilder navigatorObservers,
  }) = _AutoTabsRouterIndexedStack;

  const factory AutoTabsRouter.pageView({
    Key? key,
    required List<PageRouteInfo> routes,
    AutoTabsPageViewBuilder? builder,
    int homeIndex,
    bool animatePageTransition,
    Axis scrollDirection,
    Duration duration,
    Curve curve,
    bool inheritNavigatorObservers,
    NavigatorObserversBuilder navigatorObservers,
    ScrollPhysics? physics,
    DragStartBehavior dragStartBehavior,
  }) = AutoTabsRouterPageView;

  const factory AutoTabsRouter.tabBar({
    Key? key,
    required List<PageRouteInfo> routes,
    AutoTabsTabBarBuilder? builder,
    int homeIndex,
    Duration? duration,
    Axis scrollDirection,
    Curve curve,
    bool inheritNavigatorObservers,
    NavigatorObserversBuilder navigatorObservers,
    ScrollPhysics? physics,
    DragStartBehavior dragStartBehavior,
  }) = _AutoTabsRouterTabBar;

  const factory AutoTabsRouter.builder({
    Key? key,
    required List<PageRouteInfo> routes,
    required AutoTabsBuilder builder,
    OnNavigationChanged? onNavigate,
    OnNavigationChanged? onRouterReady,
    int homeIndex,
    bool inheritNavigatorObservers,
    NavigatorObserversBuilder navigatorObservers,
  }) = _AutoTabsRouterBuilder;

  static TabsRouter of(BuildContext context, {bool watch = false}) {
    var scope = TabsRouterScope.of(context, watch: watch);
    assert(() {
      if (scope == null) {
        throw FlutterError(
            'AutoTabsRouter operation requested with a context that does not include an AutoTabsRouter.\n'
            'The context used to retrieve the AutoTabsRouter must be that of a widget that '
            'is a descendant of an AutoTabsRouter widget.');
      }
      return true;
    }());
    return scope!.controller;
  }
}

abstract class _AutoTabsRouterState extends State<AutoTabsRouter> {
  TabsRouter? _controller;
  late RoutingController _parentController;

  TabsRouter? get controller => _controller;
  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parentRoute = RouteData.of(context);
    if (_controller == null) {
      final parentScope = RouterScope.of(context, watch: true);
      _inheritableObserversBuilder = () {
        var observers = widget.navigatorObservers();
        if (!widget.inheritNavigatorObservers) {
          return observers;
        }
        var inheritedObservers = parentScope.inheritableObserversBuilder();
        return inheritedObservers + observers;
      };
      _navigatorObservers = _inheritableObserversBuilder();
      _parentController = parentScope.controller;
      _controller = TabsRouter(
        parent: _parentController,
        key: parentRoute.key,
        homeIndex: widget.homeIndex,
        routeData: parentRoute,
        routeCollection: _parentController.routeCollection.subCollectionOf(
          parentRoute.name,
        ),
        pageBuilder: _parentController.pageBuilder,
      );
      _parentController.attachChildController(_controller!);
      _setupController();
    }
  }

  void _setupController();

  @override
  void dispose() {
    if (_controller != null) {
      _controller!.dispose();
      _parentController.removeChildController(_controller!);
      _controller = null;
    }
    super.dispose();
  }
}

// -----------------------------------------------------------
class _AutoTabsRouterIndexedStack extends AutoTabsRouter {
  final AnimatedIndexedStackBuilder? builder;
  final Duration duration;
  final Curve curve;
  final bool lazyLoad;

  const _AutoTabsRouterIndexedStack({
    Key? key,
    required List<PageRouteInfo> routes,
    this.lazyLoad = true,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.ease,
    this.builder,
    int homeIndex = -1,
    bool inheritNavigatorObservers = true,
    NavigatorObserversBuilder navigatorObservers = AutoRouterDelegate.defaultNavigatorObserversBuilder,
  }) : super._(
          key: key,
          routes: routes,
          inheritNavigatorObservers: inheritNavigatorObservers,
          navigatorObservers: navigatorObservers,
          homeIndex: homeIndex,
        );

  @override
  _AutoTabsRouterIndexedStackState createState() => _AutoTabsRouterIndexedStackState();
}

class _AutoTabsRouterIndexedStackState extends _AutoTabsRouterState with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  int _index = 0;
  late int _tabsHash;

  _AutoTabsRouterIndexedStack get typedWidget => widget as _AutoTabsRouterIndexedStack;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: typedWidget.duration,
    );
    _animation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: typedWidget.curve,
      ),
    );
    _tabsHash = const ListEquality().hash(widget.routes);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void _setupController() {
    assert(_controller != null);
    _controller!.setupRoutes(widget.routes);
    _index = _controller!.activeIndex;
    _animationController.value = 1.0;
    _controller!.addListener(() {
      if (_controller!.activeIndex != _index) {
        setState(() {
          _index = _controller!.activeIndex;
        });
        _animationController.forward(from: 0.0);
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant AutoTabsRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const ListEquality().equals(widget.routes, oldWidget.routes)) {
      _controller!.replaceAll(widget.routes, oldWidget.routes[_index]);
      _tabsHash = const ListEquality().hash(widget.routes);
      setState(() {
        _index = _controller!.activeIndex;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final stack = _controller!.stack;
    final builder = typedWidget.builder ?? _defaultBuilder;
    final stateHash = controller!.stateHash;

    final builderChild = stack.isEmpty
        ? Container(color: Theme.of(context).scaffoldBackgroundColor)
        : _IndexedStackBuilder(
            activeIndex: _index,
            tabsHash: _tabsHash,
            lazyLoad: typedWidget.lazyLoad,
            animation: _animation,
            navigatorObservers: _navigatorObservers,
            itemBuilder: (BuildContext context, int index) {
              return stack[index].buildPage(context);
            },
            stack: stack,
          );

    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      stateHash: stateHash,
      navigatorObservers: _navigatorObservers,
      child: TabsRouterScope(
        controller: _controller!,
        stateHash: stateHash,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) => builder(
            context,
            child ?? builderChild,
            _animation,
          ),
          child: builderChild,
        ),
      ),
    );
  }

  Widget _defaultBuilder(_, child, animation) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class _IndexedStackBuilder extends StatefulWidget {
  const _IndexedStackBuilder({
    Key? key,
    required this.activeIndex,
    required this.itemBuilder,
    required this.navigatorObservers,
    required this.stack,
    required this.lazyLoad,
    required this.tabsHash,
    required this.animation,
  }) : super(key: key);

  final int activeIndex;
  final IndexedWidgetBuilder itemBuilder;
  final bool lazyLoad;
  final List<AutoRoutePage> stack;
  final List<NavigatorObserver> navigatorObservers;
  final int tabsHash;
  final Animation<double> animation;

  @override
  _IndexedStackBuilderState createState() => _IndexedStackBuilderState();
}

class _IndexedStackBuilderState extends State<_IndexedStackBuilder> with _RouteAwareTabsMixin<_IndexedStackBuilder> {
  final _dummyWidget = const SizedBox.shrink();
  final _initializedPagesTracker = <int, bool>{};

  @override
  List<RouteMatch> get routes => widget.stack.map((e) => e.routeData.route).toList();

  @override
  List<NavigatorObserver> get observers => widget.navigatorObservers;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  void _setup() {
    for (var i = 0; i < widget.stack.length; ++i) {
      if (i == widget.activeIndex || !widget.lazyLoad) {
        _initializedPagesTracker[i] = true;
        _didInitTabRoute(i);
      } else {
        _initializedPagesTracker[i] = false;
      }
    }
  }

  @override
  void didUpdateWidget(_IndexedStackBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabsHash != oldWidget.tabsHash) {
      _initializedPagesTracker.clear();
      _setup();
      return;
    }
    if (widget.lazyLoad && _initializedPagesTracker[widget.activeIndex] != true) {
      _initializedPagesTracker[widget.activeIndex] = true;
      _didInitTabRoute(widget.activeIndex, oldWidget.activeIndex);
    } else if (widget.activeIndex != oldWidget.activeIndex) {
      _didChangeTabRoute(widget.activeIndex, oldWidget.activeIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      key: ValueKey(widget.tabsHash),
      index: widget.activeIndex,
      sizing: StackFit.expand,
      children: List.generate(
        widget.stack.length,
        (index) {
          if (!widget.stack[index].maintainState && index != widget.activeIndex) {
            _initializedPagesTracker[index] = false;
          }
          final isInitialized = _initializedPagesTracker[index] == true;
          return isInitialized ? widget.itemBuilder(context, index) : _dummyWidget;
        },
      ),
    );
  }
}

class AutoTabsRouterPageView extends AutoTabsRouter {
  final AutoTabsPageViewBuilder? _pageViewModeBuilder;
  final bool animatePageTransition;
  final Duration duration;
  final Curve curve;
  final Axis scrollDirection;
  final ScrollPhysics? physics;
  final DragStartBehavior dragStartBehavior;

  const AutoTabsRouterPageView({
    Key? key,
    required List<PageRouteInfo> routes,
    AutoTabsPageViewBuilder? builder,
    int homeIndex = -1,
    this.scrollDirection = Axis.horizontal,
    this.animatePageTransition = true,
    this.duration = kTabScrollDuration,
    this.curve = Curves.easeInOut,
    this.physics,
    this.dragStartBehavior = DragStartBehavior.start,
    bool inheritNavigatorObservers = true,
    NavigatorObserversBuilder navigatorObservers = AutoRouterDelegate.defaultNavigatorObserversBuilder,
  })  : _pageViewModeBuilder = builder,
        super._(
          key: key,
          routes: routes,
          homeIndex: homeIndex,
          navigatorObservers: navigatorObservers,
          inheritNavigatorObservers: inheritNavigatorObservers,
        );

  @override
  AutoTabsRouterPageViewState createState() => AutoTabsRouterPageViewState();
}

class AutoTabsRouterPageViewState extends _AutoTabsRouterState with _RouteAwareTabsMixin<AutoTabsRouter> {
  late PageController _pageController;

  @override
  void _setupController() {
    assert(_controller != null);
    _controller!.setupRoutes(widget.routes);
    _updatePageController();
    _didInitTabRoute(_controller!.activeIndex);
    _controller!.addListener(() {
      var controllerPage = 0;
      try {
        controllerPage = _pageController.page!.toInt();
      } catch (e) {
        controllerPage = 0;
      }
      if (_controller!.activeIndex != controllerPage) {
        _didChangeTabRoute(_controller!.activeIndex, _controller!.previousIndex!);
      }
    });
  }

  void _updatePageController() {
    _pageController = PageController(
      initialPage: _controller!.activeIndex,
    );
  }

  @override
  void didUpdateWidget(covariant AutoTabsRouterPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const ListEquality().equals(widget.routes, oldWidget.routes)) {
      _controller!.replaceAll(widget.routes, oldWidget.routes[_controller!.activeIndex]);
      _updatePageController();
    }
  }

  AutoTabsRouterPageView get typedWidget => widget as AutoTabsRouterPageView;

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final builder = typedWidget._pageViewModeBuilder ?? _defaultPageViewBuilder;
    final stateHash = controller!.stateHash;
    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      stateHash: stateHash,
      navigatorObservers: _navigatorObservers,
      child: TabsRouterScope(
        controller: _controller!,
        stateHash: stateHash,
        child: Builder(builder: (context) {
          return builder(
            context,
            AutoPageView(
              scrollDirection: typedWidget.scrollDirection,
              physics: typedWidget.physics,
              dragStartBehavior: typedWidget.dragStartBehavior,
              controller: _pageController,
              router: _controller!,
            ),
            _pageController,
          );
        }),
      ),
    );
  }

  Widget _defaultPageViewBuilder(_, Widget child, __) {
    return child;
  }

  @override
  List<NavigatorObserver> get observers => _navigatorObservers;

  @override
  List<RouteMatch> get routes => _controller!.stackData.map((e) => e.route).toList();
}

class _AutoTabsRouterTabBar extends AutoTabsRouter {
  final AutoTabsTabBarBuilder? builder;
  final Duration? duration;
  final Curve curve;
  final ScrollPhysics? physics;
  final DragStartBehavior dragStartBehavior;
  final Axis scrollDirection;
  const _AutoTabsRouterTabBar({
    Key? key,
    required List<PageRouteInfo> routes,
    this.scrollDirection = Axis.horizontal,
    this.builder,
    int homeIndex = -1,
    this.duration,
    this.curve = Curves.ease,
    bool inheritNavigatorObservers = true,
    NavigatorObserversBuilder navigatorObservers = AutoRouterDelegate.defaultNavigatorObserversBuilder,
    this.physics,
    this.dragStartBehavior = DragStartBehavior.start,
  }) : super._(
          key: key,
          routes: routes,
          homeIndex: homeIndex,
          navigatorObservers: navigatorObservers,
          inheritNavigatorObservers: inheritNavigatorObservers,
        );

  @override
  _AutoTabsRouterTabBarState createState() => _AutoTabsRouterTabBarState();
}

class _AutoTabsRouterTabBarState extends _AutoTabsRouterState
    with _RouteAwareTabsMixin<AutoTabsRouter>, TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void _setupController() {
    assert(_controller != null);
    _controller!.setupRoutes(widget.routes);
    _updateTabController();
    _didInitTabRoute(_controller!.activeIndex);
    _controller!.addListener(() {
      if (_controller!.activeIndex != _controller!.previousIndex) {
        _didChangeTabRoute(
          _controller!.activeIndex,
          _controller!.previousIndex ?? 0,
        );
        _tabController.animateTo(
          _controller!.activeIndex,
          duration: typedWidget.duration,
          curve: typedWidget.curve,
        );
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _updateTabController() {
    _tabController = TabController(
      initialIndex: _controller!.activeIndex,
      length: _controller!.pageCount,
      vsync: this,
    );
    _tabController.addListener(() {
      _controller!.setActiveIndex(_tabController.index);
    });
  }

  @override
  void didUpdateWidget(covariant _AutoTabsRouterTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const ListEquality().equals(widget.routes, oldWidget.routes)) {
      _controller!.replaceAll(widget.routes, oldWidget.routes[_tabController.index]);
      _updateTabController();
    }
  }

  _AutoTabsRouterTabBar get typedWidget => widget as _AutoTabsRouterTabBar;

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final builder = typedWidget.builder ?? _defaultPageViewBuilder;
    final stateHash = controller!.stateHash;
    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      stateHash: stateHash,
      navigatorObservers: _navigatorObservers,
      child: TabsRouterScope(
        controller: _controller!,
        stateHash: stateHash,
        child: Builder(builder: (context) {
          return builder(
            context,
            AutoTabView(
              scrollDirection: typedWidget.scrollDirection,
              physics: typedWidget.physics,
              dragStartBehavior: typedWidget.dragStartBehavior,
              controller: _tabController,
              router: _controller!,
            ),
            _tabController,
          );
        }),
      ),
    );
  }

  Widget _defaultPageViewBuilder(_, Widget child, __) {
    return child;
  }

  @override
  List<NavigatorObserver> get observers => _navigatorObservers;

  @override
  List<RouteMatch> get routes => _controller!.stackData.map((e) => e.route).toList();
}

class _AutoTabsRouterBuilder extends AutoTabsRouter {
  final AutoTabsBuilder builder;
  final OnNavigationChanged? onNavigate;
  final OnNavigationChanged? onRouterReady;

  const _AutoTabsRouterBuilder({
    Key? key,
    required List<PageRouteInfo> routes,
    this.onNavigate,
    this.onRouterReady,
    required this.builder,
    int homeIndex = -1,
    bool inheritNavigatorObservers = true,
    NavigatorObserversBuilder navigatorObservers = AutoRouterDelegate.defaultNavigatorObserversBuilder,
  }) : super._(
          key: key,
          routes: routes,
          homeIndex: homeIndex,
          navigatorObservers: navigatorObservers,
          inheritNavigatorObservers: inheritNavigatorObservers,
        );

  @override
  _AutoTabsRouterBuilderState createState() => _AutoTabsRouterBuilderState();
}

class _AutoTabsRouterBuilderState extends _AutoTabsRouterState with _RouteAwareTabsMixin<AutoTabsRouter> {
  @override
  void _setupController() {
    assert(_controller != null);
    _controller!.setupRoutes(widget.routes);
    typedWidget.onRouterReady?.call(_controller!);
    _didInitTabRoute(_controller!.activeIndex);
    _controller!.addListener(() {
      if (_controller!.activeIndex != _controller!.previousIndex) {
        _didChangeTabRoute(_controller!.activeIndex, _controller!.previousIndex ?? 0);
        typedWidget.onNavigate?.call(_controller!);
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant _AutoTabsRouterBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!const ListEquality().equals(widget.routes, oldWidget.routes)) {
      _controller!.replaceAll(widget.routes, oldWidget.routes[_controller!.activeIndex]);
      typedWidget.onNavigate?.call(_controller!);
    }
  }

  _AutoTabsRouterBuilder get typedWidget => widget as _AutoTabsRouterBuilder;

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final stack = _controller!.stack;
    final builder = typedWidget.builder;
    final stateHash = controller!.stateHash;
    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      stateHash: stateHash,
      navigatorObservers: _navigatorObservers,
      child: TabsRouterScope(
        controller: _controller!,
        stateHash: stateHash,
        child: Builder(builder: (context) {
          return builder(
            context,
            List.generate(
              stack.length,
              (index) => KeepAliveTab(
                key: ValueKey(index),
                page: stack[index],
              ),
            ),
            _controller!,
          );
        }),
      ),
    );
  }

  @override
  List<NavigatorObserver> get observers => _navigatorObservers;

  @override
  List<RouteMatch> get routes => _controller!.stackData.map((e) => e.route).toList();
}

mixin _RouteAwareTabsMixin<T extends StatefulWidget> on State<T> {
  List<NavigatorObserver> get observers;

  List<RouteMatch> get routes;

  void _didInitTabRoute(int index, [int previous = -1]) {
    observers.whereType<AutoRouterObserver>().forEach((observer) {
      TabPageRoute? previousRoute;
      if (previous != -1) {
        previousRoute = TabPageRoute(routeInfo: routes[previous], index: previous);
      }
      observer.didInitTabRoute(
        TabPageRoute(routeInfo: routes[index], index: index),
        previousRoute,
      );
    });
  }

  void _didChangeTabRoute(int index, int previous) {
    observers.whereType<AutoRouterObserver>().forEach((observer) {
      observer.didChangeTabRoute(
        TabPageRoute(routeInfo: routes[index], index: index),
        TabPageRoute(routeInfo: routes[previous], index: previous),
      );
    });
  }
}

class KeepAliveTab extends StatefulWidget {
  const KeepAliveTab({
    Key? key,
    required this.page,
  }) : super(key: key);
  final AutoRoutePage page;

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.page.buildPage(context);
  }

  @override
  bool get wantKeepAlive => widget.page.maintainState;
}
