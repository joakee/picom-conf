#version 330
#define PI 3.14159265
#define BORDER 200
#define WAVE_SPEED 1.0
#define WAVE_FREQUENCY 1.0
#define WAVE_AMPLITUDE 10.0
#define BASE_COLOR vec4(0.216, 0.337, 0.373, 1)
#define BG_COLOR vec4(0, 0, 0, 1)

// Monitor geometry (absolute pixel rects: x, y, width, height), so the icon
// effect and vignette are centered on each physical monitor instead of the
// center of the whole (potentially multi-monitor) window texture.
//
// Override both from picom.conf via the shader's "defines" table, e.g.:
//   shader = {
//     path = "lock.glsl";
//     defines = {
//       NUM_MONITORS = "2";
//       MONITOR_RECTS = "vec4[2](vec4(0.0, 0.0, 1920.0, 1080.0), vec4(0.0, 1080.0, 1920.0, 1080.0))";
//     };
//   };
//
// If left unset, defaults to a single "monitor" spanning the whole window,
// which reproduces the old (pre-multi-monitor) behavior.
#ifndef NUM_MONITORS
#define NUM_MONITORS 1
#endif
#ifndef MONITOR_RECTS
#define MONITOR_RECTS vec4[1](vec4(0.0, 0.0, float(textureSize(tex, 0).x), float(textureSize(tex, 0).y)))
#endif


in vec2 texcoord;             // texture coordinate of the fragment
uniform sampler2D tex;        // texture of the window

uniform float time; // Time in miliseconds.
ivec2 window_size = textureSize(tex, 0); // Size of the window
vec4 monitor_rects[NUM_MONITORS] = MONITOR_RECTS; // Per-monitor rects within the window
uniform float icon_factor = 12.0;
uniform float shadow_cutoff = 1; // How "early" the shadow starts affecting
                                 // pixels close to the edges
                                 // I'd keep this value very close to 1
uniform int shadow_intensity = 3; // Intensity level of the shadow effect (from 1 to 5)

// Finds which monitor rect a given (absolute, window-space) coordinate falls
// inside. Falls back to the first monitor if it's outside all of them (can
// happen for a pixel right on a shared edge due to float rounding).
vec4 get_monitor_rect(vec2 coords)
{
    for (int i = 0; i < NUM_MONITORS; i++)
    {
        vec4 r = monitor_rects[i];
        if (coords.x >= r.x && coords.x < r.x + r.z &&
            coords.y >= r.y && coords.y < r.y + r.w)
        {
            return r;
        }
    }
    return monitor_rects[0];
}

// These shaders work by using a pinhole camera and raycasting
// The window 3d objects will always be (somewhat) centered at (0, 0, 0)
struct pinhole_camera
{
    float focal_offset; // Distance along the Z axis between the camera
                        // center and the focal point. Use negative values
                        // so the image doesn't flip
                        // This kinda works like FOV in games

    // Transformations
    // Use these to modify the coordinate system of the camera plane
    vec3 rotations; // Rotations in radians around each axis
                    // The camera plane rotates around
                    // its center point, not the origin

    vec3 translations; // Translations in pixels along each axis

    vec3 deformations; // Deforms the camera. Higher values on each axis
                       // means the window will be squashed in that axis

    // ---------------------------------------------------------------//

    // "Aftervalues"
    // These will be set later with setup_camera(), leave them as 0
    vec3 base_x;
    vec3 base_y;
    vec3 base_z;
    vec3 center_point;
    vec3 focal_point;
};


// Sets up a camera by applying transformations and
// calculating xyz vector basis
pinhole_camera setup_camera(pinhole_camera camera, float ppa)
{
    // Apply translations
    camera.center_point += camera.translations;

    // Apply rotations
    // We initialize our vector basis as normalized vectors
    // in each axis * our deformations vector
    camera.base_x = vec3(camera.deformations.x, 0, 0);
    camera.base_y = vec3(0, camera.deformations.y, 0);
    camera.base_z = vec3(0, 0, camera.deformations.z);


    // Then we rotate them around following our rotations vector:
    // First save these values to avoid redundancy
    float cosx = cos(camera.rotations.x);
    float cosy = cos(camera.rotations.y);
    float cosz = cos(camera.rotations.z);
    float sinx = sin(camera.rotations.x);
    float siny = sin(camera.rotations.y);
    float sinz = sin(camera.rotations.z);

    // Declare a buffer vector we will use to apply multiple changes at once
    vec3 tmp = vec3(0);

    // Rotations for base_x:
    tmp = camera.base_x;
    // X axis:
    tmp.y =  camera.base_x.y * cosx - camera.base_x.z * sinx;
    tmp.z =  camera.base_x.y * sinx + camera.base_x.z * cosx;
    camera.base_x = tmp;
    // Y axis:
    tmp.x =  camera.base_x.x * cosy + camera.base_x.z * siny;
    tmp.z = -camera.base_x.x * siny + camera.base_x.z * cosy;
    camera.base_x = tmp;
    // Z axis:
    tmp.x =  camera.base_x.x * cosz - camera.base_x.y * sinz;
    tmp.y =  camera.base_x.x * sinz + camera.base_x.y * cosz;
    camera.base_x = tmp;

    // Rotations for base_y:
    tmp = camera.base_y;
    // X axis:
    tmp.y =  camera.base_y.y * cosx - camera.base_y.z * sinx;
    tmp.z =  camera.base_y.y * sinx + camera.base_y.z * cosx;
    camera.base_y = tmp;
    // Y axis:
    tmp.x =  camera.base_y.x * cosy + camera.base_y.z * siny;
    tmp.z = -camera.base_y.x * siny + camera.base_y.z * cosy;
    camera.base_y = tmp;
    // Z axis:
    tmp.x =  camera.base_y.x * cosz - camera.base_y.y * sinz;
    tmp.y =  camera.base_y.x * sinz + camera.base_y.y * cosz;
    camera.base_y = tmp;

    // Rotations for base_z:
    tmp = camera.base_z;
    // X axis:
    tmp.y =  camera.base_z.y * cosx - camera.base_z.z * sinx;
    tmp.z =  camera.base_z.y * sinx + camera.base_z.z * cosx;
    camera.base_z = tmp;
    // Y axis:
    tmp.x =  camera.base_z.x * cosy + camera.base_z.z * siny;
    tmp.z = -camera.base_z.x * siny + camera.base_z.z * cosy;
    camera.base_z = tmp;
    // Z axis:
    tmp.x =  camera.base_z.x * cosz - camera.base_z.y * sinz;
    tmp.y =  camera.base_z.x * sinz + camera.base_z.y * cosz;
    camera.base_z = tmp;

    // Now that we have our transformed 3d orthonormal base
    // we can calculate our focal point
    camera.focal_point = camera.center_point + camera.base_z * camera.focal_offset;

    // Return our set up camera
    return camera;
}
// Helper function for the RGB shift (chromatic aberration)
vec2 curve(vec2 uv)
{
    uv = (uv - 0.5) * 2.0;
    uv *= 1.1;
    uv.x *= 1.0 + pow((abs(uv.y) / 5.0), 2.0);
    uv.y *= 1.0 + pow((abs(uv.x) / 4.0), 2.0);
    uv = (uv / 2.0) + 0.5;
    return uv;
}


// CRT effect shader
vec4 crt_shader(vec2 coords)
{
    // Parameters - feel free to adjust these
    float scanline_intensity = 0.125;      // How dark the scanlines are
    float rgb_shift = 2.0;                 // How much RGB shifting occurs
    float vignette_intensity = 0.2;        // How dark the corners get
    float screen_curve = 0.5;             // How much screen curvature

    // Convert coords to UV space (0 to 1)
    vec2 uv = coords / vec2(window_size);

    // Apply screen curvature
    vec2 curved_uv = mix(uv, curve(uv), screen_curve);

    // If UV is outside bounds, return black
    if (curved_uv.x < 0.0 || curved_uv.x > 1.0 ||
        curved_uv.y < 0.0 || curved_uv.y > 1.0)
        return vec4(0.0, 0.0, 0.0, 1.0);

    // Convert curved UV back to pixel coordinates
    vec2 screen_pos = curved_uv * vec2(window_size);

    // Chromatic aberration
    vec4 color;
    color.r = texelFetch(tex, ivec2(screen_pos + vec2(rgb_shift, 0.0)), 0).r;
    color.g = texelFetch(tex, ivec2(screen_pos), 0).g;
    color.b = texelFetch(tex, ivec2(screen_pos - vec2(rgb_shift, 0.0)), 0).b;
    color.a = 1.0;

    // Scanlines
    float scanline = sin(screen_pos.y * 0.7) * 0.5 + 0.5;
    color.rgb *= 1.0 - (scanline * scanline_intensity);

    // Vertical sync lines (more subtle)
    float vertical_sync = sin(screen_pos.x * 2.0) * 0.5 + 0.5;
    color.rgb *= 1.0 - (vertical_sync * scanline_intensity * 0.5);

    // Vignette (darker corners)
    vec2 center_dist = curved_uv - vec2(0.5);
    float vignette = 1.0 - (dot(center_dist, center_dist) * vignette_intensity);
    color.rgb *= vignette;

    // Brightness and contrast adjustments
    color.rgb *= 1.2;  // Brightness boost
    color.rgb = pow(color.rgb, vec3(1.2)); // Contrast boost

    // Add subtle noise to simulate CRT noise
    float noise = fract(sin(dot(curved_uv, vec2(12.9898, 78.233))) * 43758.5453);
    color.rgb += (noise * 0.02 - 0.01); // Very subtle noise

    return color;
}

// Gets a pixel from the end of a ray projected to an axis
vec4 get_pixel_from_projection(float t, pinhole_camera camera, vec3 focal_vector, float ppa,
                                vec2 mon_center, float icon_radius)
{
    // If the point we end up in is behind our camera, don't "render" it
    if (t < 1)
    {
        return BG_COLOR;
    }

    // Then we multiply our focal vector by t and add our focal point to it
    // to end up in a point inside the window plane
    vec3 intersection = focal_vector * t + camera.focal_point;


    // Save necessary coordinates
    vec2 cam_coords = intersection.xy;
    float cam_coords_length = length(cam_coords);

    // If pixel is outside of our icon region
    // return an empty pixel
    float local_icon_radius = icon_radius - 50 + 60 * ppa;
    if (cam_coords_length > local_icon_radius)
    {
        return vec4(0);
    }

    // Fetch the pixel
    cam_coords += mon_center;
    vec4 pixel = texelFetch(tex, ivec2(cam_coords), 0);
    pixel = crt_shader(cam_coords);
    if (pixel.xyz == vec3(0))
    {
        return BASE_COLOR;
    }

    pixel.w = 0.9;
    return pixel;
}

// Gets a pixel through the camera using coords as coordinates in
// the camera plane
vec4 get_pixel_through_camera(vec2 coords, pinhole_camera camera, float ppa,
                               vec2 mon_center, float icon_radius)
{
    // Offset coords
    coords -= mon_center;

    // Find the pixel 3d position using the camera vector basis
    vec3 pixel_3dposition =   camera.center_point
                            + coords.x * camera.base_x
                            + coords.y * camera.base_y;

    // Get the vector going from the focal point to the pixel in 3d sapace
    vec3 focal_vector = pixel_3dposition - camera.focal_point;

    // Following the sphere EQ (with Y axis as center)
    // x^2 + y^2 + z^2 = r^2
    float r = icon_radius * 2 / PI + 33;

    // Then there's a line going from our focal point to the sphere
    // which we can describe as:
    // x(t) = focal_point.x + focal_vector.x * t
    // y(t) = focal_point.y + focal_vector.y * t
    // z(t) = focal_point.z + focal_vector.z * t
    // We substitute x, y and z with x(t) and z(t) in the sphere EQ
    // Solving for t we get a cuadratic EQ which we solve with the
    // cuadratic formula:

    // We calculate focal vector and focal point values squared
    // to avoid redundancy
    vec3 fvsqr;
    vec3 fpsqr;

    fvsqr.x = pow(focal_vector.x,2);
    fvsqr.y = pow(focal_vector.y,2);
    fvsqr.z = pow(focal_vector.z,2);

    fpsqr.x = pow(camera.focal_point.x,2);
    fpsqr.y = pow(camera.focal_point.y,2);
    fpsqr.z = pow(camera.focal_point.z,2);

    // Coeficients of our EQ
    float a = fvsqr.x + fvsqr.y + fvsqr.z;
    float b = 2*(camera.focal_point.x*focal_vector.x
                +camera.focal_point.y*focal_vector.y
                +camera.focal_point.z*focal_vector.z);
    float c = fpsqr.x + fpsqr.y + fpsqr.z - pow(r,2);

    // If there are no real roots, then there's no intersection and we
    // return an empty pixel
    float formulasqrt = pow(b,2)-4*a*c;
    if (formulasqrt < 0)
    {
        return vec4(0);
    }

    // A ray through a sphere has two intersections: the near (front) surface
    // and the far (back) surface. Only render the near one, so the content
    // showing through the sphere appears as a single image instead of the
    // front and back surfaces both sampling the texture and blending together.
    float t_near = min((-b + sqrt(formulasqrt))/(2*a), (-b - sqrt(formulasqrt))/(2*a));

    return get_pixel_from_projection(t_near, camera, focal_vector, ppa, mon_center, icon_radius);
}

// Default window post-processing:
// 1) invert color
// 2) opacity / transparency
// 3) max-brightness clamping
// 4) rounded corners
vec4 default_post_processing(vec4 c);

vec4 window_shader() {
    vec4 c = texelFetch(tex, ivec2(texcoord), 0);
    float post_proc_alpha = default_post_processing(c).w; // <-- Use that to animate things when window is destroyed

    // Which physical monitor is this fragment on? Everything below is
    // computed relative to that monitor's own center/size, not the size of
    // the whole (possibly multi-monitor) window texture.
    vec4 mon_rect = get_monitor_rect(texcoord);
    vec2 mon_center = mon_rect.xy + mon_rect.zw * 0.5;
    vec2 mon_size = mon_rect.zw;
    float icon_radius = mon_size.y / icon_factor;

    if (distance(texcoord, mon_center) <= icon_radius)
    {
        float cam_offset = mon_size.y*3;

        float time_offset = pow((1-post_proc_alpha),2) ;
        float time_cyclic = mod(4*(time/10000 - time_offset),2);
        pinhole_camera rotate_around_origin =
            pinhole_camera(-cam_offset,
                           vec3(0,-time_cyclic*PI-PI/2,0),
                           vec3(cos(time_cyclic*PI)*mon_size.y*0.4,
                                0,
                                sin(time_cyclic*PI)*mon_size.y*0.4),
                           vec3(1,1,1),
                           vec3(0),
                           vec3(0),
                           vec3(0),
                           vec3(0),
                           vec3(0));
        pinhole_camera transformed_cam = setup_camera(rotate_around_origin, post_proc_alpha);
        vec4 icon_c = get_pixel_through_camera(texcoord, transformed_cam, post_proc_alpha, mon_center, icon_radius);
        // Blend over the real window content (rather than fully replacing it)
        // so i3lock's own indicator (typing dots, verify/wrong colors) still
        // shows through wherever the icon effect itself is transparent.
        c = mix(c, icon_c, icon_c.a);
    }
    return default_post_processing(c);
}
