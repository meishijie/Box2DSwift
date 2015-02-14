/**
Copyright (c) 2006-2014 Erin Catto http://www.box2d.org
Copyright (c) 2015 - Yohei Yoshihara

This software is provided 'as-is', without any express or implied
warranty.  In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
claim that you wrote the original software. If you use this software
in a product, an acknowledgment in the product documentation would be
appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.

3. This notice may not be removed or altered from any source distribution.

This version of box2d was developed by Yohei Yoshihara. It is based upon
the original C++ code written by Erin Catto.
*/

import Foundation

/// This holds contact filtering data.
public struct b2Filter {
  public init() {
    categoryBits = 0x0001
    maskBits = 0xFFFF
    groupIndex = 0
  }
  
  /// The collision category bits. Normally you would just set one bit.
  public var categoryBits : UInt16
  
  /// The collision mask bits. This states the categories that this
  /// shape would accept for collision.
  public var maskBits : UInt16
  
  /// Collision groups allow a certain group of objects to never collide (negative)
  /// or always collide (positive). Zero means no collision group. Non-zero group
  /// filtering always wins against the mask bits.
  public var groupIndex : Int16
}

/// A fixture definition is used to create a fixture. This class defines an
/// abstract fixture definition. You can reuse fixture definitions safely.
public class b2FixtureDef {
  /// The constructor sets the default fixture definition values.
  public init() {
    shape = nil
    userData = nil
    friction = 0.2
    restitution = 0.0
    density = 0.0
    isSensor = false
    filter = b2Filter()
  }
  
  /// The shape, this must be set. The shape will be cloned, so you
  /// can create the shape on the stack.
  public var shape: b2Shape!
  
  /// Use this to store application specific fixture data.
  public var userData: AnyObject?
  
  /// The friction coefficient, usually in the range [0,1].
  public var friction: b2Float
  
  /// The restitution (elasticity) usually in the range [0,1].
  public var restitution: b2Float
  
  /// The density, usually in kg/m^2.
  public var density: b2Float
  
  /// A sensor shape collects contact information but never generates a collision
  /// response.
  public var isSensor: Bool
  
  /// Contact filtering data.
  public var filter: b2Filter
}

/// This proxy is used internally to connect fixtures to the broad-phase.
public struct b2FixtureProxy {
  init(_ fixture: b2Fixture) {
    self.fixture = fixture
  }
  var aabb = b2AABB()
  unowned var fixture: b2Fixture // ** parent **
  var childIndex = 0
  var proxyId = 0
}

/// A fixture is used to attach a shape to a body for collision detection. A fixture
/// inherits its transform from its parent. Fixtures hold additional non-geometric data
/// such as friction, collision filters, etc.
/// Fixtures are created via b2Body::CreateFixture.
/// @warning you cannot reuse fixtures.
public class b2Fixture : Printable {
  /// Get the type of the child shape. You can use this to down cast to the concrete shape.
  /// @return the shape type.
  public var type: b2ShapeType {
    return m_shape.type
  }
  
  /// Get the child shape. You can modify the child shape, however you should not change the
  /// number of vertices because this will crash some collision caching mechanisms.
  /// Manipulating the shape may lead to non-physical behavior.
  public var shape: b2Shape {
    return m_shape
  }
  //const b2Shape* GetShape() const
  
  /// Set if this fixture is a sensor.
  public func setSensor(sensor: Bool) {
    if sensor != m_isSensor {
      m_body.setAwake(true)
      m_isSensor = sensor
    }
  }
  
  /// Is this fixture a sensor (non-solid)?
  /// @return the true if the shape is a sensor.
  public var isSensor: Bool {
    get {
      return m_isSensor
    }
    set {
      setSensor(newValue)
    }
  }
  
  /// Set the contact filtering data. This will not update contacts until the next time
  /// step when either parent body is active and awake.
  /// This automatically calls Refilter.
  public func setFilterData(filter: b2Filter) {
    m_filter = filter
    refilter()
  }
  
  /// Get the contact filtering data.
  public var filterData: b2Filter {
    get {
      return m_filter
    }
    set {
      setFilterData(newValue)
    }
  }
  
  /// Call this if you want to establish collision that was previously disabled by b2ContactFilter::ShouldCollide.
  public func refilter() {
    // Flag associated contacts for filtering.
    var edge = m_body.getContactList()
    while edge != nil {
      var contact = edge!.contact
      var fixtureA = contact.fixtureA
      var fixtureB = contact.fixtureB
      if fixtureA === self || fixtureB === self {
        contact.flagForFiltering()
      }
      edge = edge!.next
    }
    
    var world = m_body.world
    
    if world == nil {
      return
    }
    
    // Touch each proxy so that new pairs may be created
    var broadPhase = world!.m_contactManager.m_broadPhase
    for i in 0 ..< m_proxyCount {
      broadPhase.touchProxy(m_proxies[i].proxyId)
    }
  }
  
  /// Get the parent body of this fixture. This is NULL if the fixture is not attached.
  /// @return the parent body.
  public var body: b2Body {
    return m_body
  }
  //const b2Body* GetBody() const
  
  /// Get the next fixture in the parent body's fixture list.
  /// @return the next shape.
  public func getNext() -> b2Fixture? {
    return m_next
  }
  //const b2Fixture* getNext() const
  
  /// Get the user data that was assigned in the fixture definition. Use this to
  /// store your application specific data.
  public var userData: AnyObject? {
    get {
      return m_userData
    }
    set {
      setUserData(newValue)
    }
  }
  
  /// Set the user data. Use this to store your application specific data.
  public func setUserData(data: AnyObject?) {
    m_userData = data
  }
  
  /**
  Test a point for containment in this fixture.
  
  :param: p a point in world coordinates.
  */
  public func testPoint(p: b2Vec2) -> Bool {
    return m_shape.testPoint(transform: m_body.transform, point: p)
  }
  
  /**
  Cast a ray against this shape.
  
  :param: output the ray-cast results.
  :param: input the ray-cast input parameters.
  */
  public func rayCast(inout output: b2RayCastOutput,input: b2RayCastInput, childIndex: Int) -> Bool {
    return m_shape.rayCast(&output, input: input, transform: m_body.transform, childIndex: childIndex)
  }
  
  /// Get the mass data for this fixture. The mass data is based on the density and
  /// the shape. The rotational inertia is about the shape's origin. This operation
  /// may be expensive.
  public var massData: b2MassData {
    return m_shape.computeMass(density: m_density)
  }
  
  /// Set the density of this fixture. This will _not_ automatically adjust the mass
  /// of the body. You must call b2Body::ResetMassData to update the body's mass.
  public func setDensity(density: b2Float) {
    assert(b2IsValid(density) && density >= 0.0)
    m_density = density
  }
  
  /// Get the density of this fixture.
  public var density: b2Float {
    get {
      return m_density
    }
    set {
      setDensity(newValue)
    }
  }
  
  /// Get the coefficient of friction.
  public var friction: b2Float {
    get {
      return m_friction
    }
    set {
      setFriction(newValue)
    }
  }
  
  /// Set the coefficient of friction. This will _not_ change the friction of
  /// existing contacts.
  public func setFriction(friction: b2Float) {
    m_friction = friction
  }
  
  /// Get the coefficient of restitution.
  public var restitution: b2Float {
    get {
      return m_restitution
    }
    set {
      setRestitution(newValue)
    }
  }
  
  /// Set the coefficient of restitution. This will _not_ change the restitution of
  /// existing contacts.
  public func setRestitution(restitution: b2Float) {
    m_restitution = restitution
  }
  
  /// Get the fixture's AABB. This AABB may be enlarge and/or stale.
  /// If you need a more accurate AABB, compute it using the shape and
  /// the body transform.
  public func getAABB(#childIndex: Int) -> b2AABB {
    assert(0 <= childIndex && childIndex < m_proxyCount)
    return m_proxies[childIndex].aabb
  }
  
  /// Dump this fixture to the log file.
  public func dump(bodyIndex: Int) {
    println("    b2FixtureDef fd;")
    println("    fd.friction = \(m_friction);")
    println("    fd.restitution = \(m_restitution);")
    println("    fd.density = \(m_density);")
    println("    fd.isSensor = bool(\(m_isSensor))")
    println("    fd.filter.categoryBits = uint16(\(m_filter.categoryBits))")
    println("    fd.filter.maskBits = uint16(\(m_filter.maskBits))")
    println("    fd.filter.groupIndex = int16(\(m_filter.groupIndex))")
    
    switch m_shape.m_type {
    case b2ShapeType.circle:
      let s = m_shape as! b2CircleShape
      println("    b2CircleShape shape;")
      println("    shape.m_radius = \(s.m_radius);")
      println("    shape.m_p.set(\(s.m_p.x), \(s.m_p.y))")
      
    case b2ShapeType.edge:
      let s = m_shape as! b2EdgeShape
      println("    b2EdgeShape shape;")
      println("    shape.m_radius = \(s.m_radius);")
      println("    shape.m_vertex0.set(\(s.m_vertex0.x), \(s.m_vertex0.y))")
      println("    shape.m_vertex1.set(\(s.m_vertex1.x), \(s.m_vertex1.y))")
      println("    shape.m_vertex2.set(\(s.m_vertex2.x), \(s.m_vertex2.y))")
      println("    shape.m_vertex3.set(\(s.m_vertex3.x), \(s.m_vertex3.y))")
      println("    shape.m_hasVertex0 = bool(\(s.m_hasVertex0))")
      println("    shape.m_hasVertex3 = bool(\(s.m_hasVertex3))")
      
    case b2ShapeType.polygon:
      let s = m_shape as! b2PolygonShape
      println("    b2PolygonShape shape;")
      println("    b2Vec2 vs[\(b2_maxPolygonVertices)];")
      for i in 0 ..< s.m_count {
        println("    vs[\(i)].set(\(s.m_vertices[i].x), \(s.m_vertices[i].y))")
      }
      println("    shape.set(vs, \(s.m_count))")
      
    case b2ShapeType.chain:
      let s = m_shape as! b2ChainShape
      println("    b2ChainShape shape;")
      println("    b2Vec2 vs[\(s.m_count)];")
      for i in 0 ..< s.m_count {
        println("    vs[\(i)].set(\(s.m_vertices[i].x), \(s.m_vertices[i].y))")
      }
      println("    shape.CreateChain(vs, \(s.m_count))")
      println("    shape.m_prevVertex.set(\(s.m_prevVertex.x), \(s.m_prevVertex.y))")
      println("    shape.m_nextVertex.set(\(s.m_nextVertex.x), \(s.m_nextVertex.y))")
      println("    shape.m_hasPrevVertex = bool(\(s.m_hasPrevVertex))")
      println("    shape.m_hasNextVertex = bool(\(s.m_hasNextVertex))")
      
    default:
      return
    }
    
    println("")
    println("    fd.shape = &shape;")
    println("")
    println("    bodies[\(bodyIndex)]->createFixture(&fd)")
  }
  
  public var description: String {
    var s = String()
    s += "b2Fixture[density=\(m_density), friction=\(m_friction), restitution=\(m_restitution), isSensor=\(m_isSensor), body=\(m_body)]"
    return s
  }
  
  // MARK: - private methods
  
  // We need separation create/destroy functions from the constructor/destructor because
  // the destructor cannot access the allocator (no destructor arguments allowed by C++).
  init(body: b2Body, def: b2FixtureDef) {
    m_userData = def.userData
    m_friction = def.friction
    m_restitution = def.restitution
    
    m_body = body
    m_next = nil
    
    m_filter = def.filter
    
    m_isSensor = def.isSensor
    
    assert(def.shape != nil)
    m_shape = def.shape.clone()
    
    // Reserve proxy space
    let childCount = m_shape.childCount
    m_proxies = [b2FixtureProxy]()
    m_proxies.reserveCapacity(childCount)
    
    m_density = def.density
  }
  
  func destroy() {
    // The proxies must be destroyed before calling this.
    assert(m_proxyCount == 0)
    
    // Free the proxy array.
    let childCount = m_shape.childCount
    m_proxies.removeAll()
    
    // Free the child shape.
    m_shape = nil
  }
  
  // These support body activation/deactivation.
  func createProxies(broadPhase: b2BroadPhase, xf: b2Transform) {
    assert(m_proxyCount == 0)
    
    // Create proxies in the broad-phase.
    let proxyCount = m_shape.childCount
    
    for var i = 0; i < proxyCount; ++i {
      var proxy = b2FixtureProxy(self)
      m_shape.computeAABB(&proxy.aabb, transform: xf, childIndex: i)
      proxy.childIndex = i
      proxy.proxyId = broadPhase.createProxy(aabb: proxy.aabb, userData: proxy)
      m_proxies.append(proxy)
    }
  }
  func destroyProxies(broadPhase: b2BroadPhase) {
    // Destroy proxies in the broad-phase.
    for i in 0 ..< m_proxyCount {
      var proxy = m_proxies[i]
      broadPhase.destroyProxy(proxy.proxyId)
    }
    
    m_proxies.removeAll()
  }
  
  func synchronize(broadPhase: b2BroadPhase, _ transform1: b2Transform, _ transform2: b2Transform) {
    if m_proxyCount == 0 {
      return
    }
    
    for i in 0 ..< m_proxyCount {
      var proxy = m_proxies[i]
      
      // Compute an AABB that covers the swept shape (may miss some rotation effect).
      var aabb1 = b2AABB(), aabb2 = b2AABB()
      m_shape.computeAABB(&aabb1, transform: transform1, childIndex: proxy.childIndex)
      m_shape.computeAABB(&aabb2, transform: transform2, childIndex: proxy.childIndex)
      
      proxy.aabb.combine(aabb1, aabb2)
      
      let displacement = transform2.p - transform1.p
      
      broadPhase.moveProxy(proxy.proxyId, aabb: proxy.aabb, displacement: displacement)
    }
  }
  
  // MARK: - variables
  var m_density: b2Float = 0.0
  
  var m_next: b2Fixture? = nil // ** linked list **
  unowned var m_body: b2Body // ** parent **
  
  var m_shape: b2Shape! = nil // ** owner **
  
  var m_friction: b2Float = 0.0
  var m_restitution: b2Float = 0.0
  
  var m_proxies = [b2FixtureProxy]() // ** owner **
  var m_proxyCount: Int { return m_proxies.count }
  
  var m_filter = b2Filter()
  var m_isSensor: Bool = false
  var m_userData: AnyObject? = nil
}
