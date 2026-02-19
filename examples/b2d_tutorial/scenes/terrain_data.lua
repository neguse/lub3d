-- Source: physicsDrivenParticles.cpp (RUBE export of physicsDrivenParticles.rube)
-- Based on iforce2d Box2D tutorials by Chris Campbell (www.iforce2d.net)
-- Altered source version: ported to Lua from original C++ code
-- License: zlib (see THIRD-PARTY-NOTICES)
--
-- Terrain data from physicsDrivenParticles.cpp (RUBE export)
-- bodies[0] = bumpy terrain (friction=0.25, classified as MAT_DIRT in particles.lua)
-- bodies[1] = flat terrain + walls (friction=0.8, classified as MAT_CONCRETE in particles.lua)
return {
    -- bodies[0]: bumpy terrain, position=(26.7841, -20.5809)
    {
        position = { 26.7841, -20.5809 },
        fixtures = {
            -- fixture 1: 4 vertices
            { friction = 0.25, vertices = {
                { 5.8115, 20.4730 },
                { 4.0326, 20.5008 },
                { -0.5178, 20.5009 },
                { -0.5178, 14.3672 },
            } },
            -- fixture 2: 3 vertices
            { friction = 0.25, vertices = {
                { 5.8115, 20.4730 },
                { 4.8325, 20.5804 },
                { 4.0326, 20.5008 },
            } },
            -- fixture 3: 4 vertices
            { friction = 0.25, vertices = {
                { 6.6353, 20.4968 },
                { 6.0025, 20.5685 },
                { 5.8115, 20.4730 },
                { -0.5178, 14.3672 },
            } },
            -- fixture 4: 4 vertices
            { friction = 0.25, vertices = {
                { 9.1663, 20.4133 },
                { 7.9008, 20.6520 },
                { 6.6353, 20.4968 },
                { -0.5178, 14.3672 },
            } },
            -- fixture 5: 4 vertices
            { friction = 0.25, vertices = {
                { 11.5659, 20.4730 },
                { 10.3243, 20.5446 },
                { 9.1663, 20.4133 },
                { -0.5178, 14.3672 },
            } },
            -- fixture 6: 4 vertices
            { friction = 0.25, vertices = {
                { 12.5927, 20.4849 },
                { 11.8286, 20.5207 },
                { 11.5659, 20.4730 },
                { -0.5178, 14.3672 },
            } },
            -- fixture 7: 6 vertices
            { friction = 0.25, vertices = {
                { 31.6907, 14.3670 },
                { 16.3229, 20.4811 },
                { 15.2127, 20.6867 },
                { 14.0134, 20.6162 },
                { 12.5927, 20.4849 },
                { -0.5178, 14.3672 },
            } },
            -- fixture 8: 4 vertices
            { friction = 0.25, vertices = {
                { 31.6907, 14.3670 },
                { 18.4221, 20.4357 },
                { 17.0769, 20.5167 },
                { 16.3229, 20.4811 },
            } },
            -- fixture 9: 4 vertices
            { friction = 0.25, vertices = {
                { 31.6907, 14.3670 },
                { 20.1457, 20.4951 },
                { 19.5910, 20.5743 },
                { 18.4221, 20.4357 },
            } },
            -- fixture 10: 5 vertices
            { friction = 0.25, vertices = {
                { 31.6907, 14.3670 },
                { 25.7326, 20.7328 },
                { 24.7024, 20.7725 },
                { 22.0278, 20.7725 },
                { 20.1457, 20.4951 },
            } },
            -- fixture 11: 3 vertices
            { friction = 0.25, vertices = {
                { 22.0278, 20.7725 },
                { 21.2156, 20.9111 },
                { 20.1457, 20.4951 },
            } },
            -- fixture 12: 3 vertices
            { friction = 0.25, vertices = {
                { 24.7024, 20.7725 },
                { 23.2760, 20.9706 },
                { 22.0278, 20.7725 },
            } },
            -- fixture 13: 6 vertices
            { friction = 0.25, vertices = {
                { 31.6907, 14.3670 },
                { 30.2496, 20.7725 },
                { 29.1996, 20.9310 },
                { 28.3675, 20.9706 },
                { 27.3175, 20.8913 },
                { 25.7326, 20.7328 },
            } },
            -- fixture 14: 3 vertices
            { friction = 0.25, vertices = {
                { 27.3175, 20.8913 },
                { 26.4656, 21.0696 },
                { 25.7326, 20.7328 },
            } },
            -- fixture 15: 6 vertices
            { friction = 0.25, vertices = {
                { 35.0242, 20.5942 },
                { 33.7166, 20.8319 },
                { 32.7657, 20.8715 },
                { 31.1807, 20.9310 },
                { 30.2496, 20.7725 },
                { 31.6907, 14.3670 },
            } },
            -- fixture 16: 3 vertices
            { friction = 0.25, vertices = {
                { 32.7657, 20.8715 },
                { 31.8147, 21.0498 },
                { 31.1807, 20.9310 },
            } },
            -- fixture 17: 3 vertices
            { friction = 0.25, vertices = {
                { 35.0242, 20.5942 },
                { 34.2713, 20.9508 },
                { 33.7166, 20.8319 },
            } },
            -- fixture 18: 5 vertices
            { friction = 0.25, vertices = {
                { 59.3194, 14.3668 },
                { 37.1381, 20.6618 },
                { 35.7176, 20.8121 },
                { 35.0242, 20.5942 },
                { 31.6907, 14.3670 },
            } },
            -- fixture 19: 4 vertices
            { friction = 0.25, vertices = {
                { 59.3194, 14.3668 },
                { 40.5046, 20.6618 },
                { 38.9015, 20.8862 },
                { 37.1381, 20.6618 },
            } },
            -- fixture 20: 5 vertices
            { friction = 0.25, vertices = {
                { 59.3194, 14.3668 },
                { 48.2956, 20.5656 },
                { 45.7307, 20.7580 },
                { 43.6787, 20.7259 },
                { 40.5046, 20.6618 },
            } },
            -- fixture 21: 3 vertices
            { friction = 0.25, vertices = {
                { 43.6787, 20.7259 },
                { 42.1077, 20.8862 },
                { 40.5046, 20.6618 },
            } },
            -- fixture 22: 3 vertices
            { friction = 0.25, vertices = {
                { 48.2956, 20.5656 },
                { 46.7887, 20.9183 },
                { 45.7307, 20.7580 },
            } },
            -- fixture 23: 6 vertices
            { friction = 0.25, vertices = {
                { 59.3194, 14.3668 },
                { 56.2790, 20.4694 },
                { 53.2973, 20.6939 },
                { 51.7904, 20.7259 },
                { 50.7644, 20.7259 },
                { 48.2956, 20.5656 },
            } },
            -- fixture 24: 3 vertices
            { friction = 0.25, vertices = {
                { 50.7644, 20.7259 },
                { 49.5140, 20.8221 },
                { 48.2956, 20.5656 },
            } },
            -- fixture 25: 3 vertices
            { friction = 0.25, vertices = {
                { 56.2790, 20.4694 },
                { 54.2271, 20.8862 },
                { 53.2973, 20.6939 },
            } },
            -- fixture 26: 4 vertices (last in body 0, right edge)
            { friction = 0.25, vertices = {
                { 59.3194, 14.3668 },
                { 59.3194, 20.5004 },
                { 58.3310, 20.5656 },
                { 56.2790, 20.4694 },
            } },
            -- fixture 27: 3 vertices
            { friction = 0.25, vertices = {
                { 58.3310, 20.5656 },
                { 57.2409, 20.7259 },
                { 56.2790, 20.4694 },
            } },
        },
    },
    -- bodies[1]: flat terrain + walls, position=(-0.0351, -20.5792)
    {
        position = { -0.0351, -20.5792 },
        fixtures = {
            -- fixture 1: flat ground left section
            { friction = 0.8, vertices = {
                { -4.8653, 20.5000 },
                { -57.7516, 20.5000 },
                { -58.6526, 14.3663 },
                { -6.3209, 14.3663 },
            } },
            -- fixture 2: left wall
            { friction = 0.8, vertices = {
                { -57.7516, 20.5000 },
                { -57.7516, 28.4915 },
                { -58.6526, 28.4915 },
                { -58.6526, 14.3663 },
            } },
            -- fixture 3: ramp bump left
            { friction = 0.8, vertices = {
                { -4.8653, 20.5000 },
                { -5.4393, 20.7387 },
                { -7.3526, 20.7387 },
                { -7.9812, 20.5000 },
            } },
            -- fixture 4: flat ground center-left
            { friction = 0.8, vertices = {
                { 11.3408, 14.3663 },
                { 8.9045, 20.5000 },
                { -4.8653, 20.5000 },
                { -6.3209, 14.3663 },
            } },
            -- fixture 5: ramp bump right (left side)
            { friction = 0.8, vertices = {
                { 11.3499, 20.5728 },
                { 10.9856, 20.8385 },
                { 9.5977, 20.8385 },
                { 8.9045, 20.5000 },
                { 11.3408, 14.3663 },
            } },
            -- fixture 6: ramp bump right (right side)
            { friction = 0.8, vertices = {
                { 13.5958, 20.5000 },
                { 12.9187, 20.8385 },
                { 11.7584, 20.8385 },
                { 11.3499, 20.5728 },
                { 11.3408, 14.3663 },
            } },
            -- fixture 7: flat ground center
            { friction = 0.8, vertices = {
                { 26.3014, 14.3655 },
                { 26.3014, 20.4991 },
                { 13.5958, 20.5000 },
                { 11.3408, 14.3663 },
            } },
            -- fixture 8: triangle (right ramp top)
            { friction = 0.8, vertices = {
                { 101.0915, 20.5728 },
                { 100.6829, 20.8385 },
                { 99.5226, 20.8385 },
            } },
            -- fixture 9: triangle
            { friction = 0.8, vertices = {
                { 101.0915, 20.5728 },
                { 99.5226, 20.8385 },
                { 98.8455, 20.5000 },
            } },
            -- fixture 10: triangle
            { friction = 0.8, vertices = {
                { 102.8436, 20.8385 },
                { 101.4557, 20.8385 },
                { 101.0915, 20.5728 },
            } },
            -- fixture 11: triangle
            { friction = 0.8, vertices = {
                { 103.5368, 20.5000 },
                { 102.8436, 20.8385 },
                { 101.0915, 20.5728 },
            } },
            -- fixture 12: bump far right area
            { friction = 0.8, vertices = {
                { 119.7939, 20.7387 },
                { 117.8806, 20.7387 },
                { 117.3067, 20.5000 },
            } },
            -- fixture 13: right wall (top portion)
            { friction = 0.8, vertices = {
                { 127.0545, 28.4915 },
                { 126.1535, 28.4915 },
                { 126.1535, 20.5000 },
            } },
            -- fixture 14: right wall (bottom-right triangle)
            { friction = 0.8, vertices = {
                { 127.0545, 14.3663 },
                { 127.0545, 28.4915 },
                { 126.1535, 20.5000 },
            } },
            -- fixture 15: right section ground (right)
            { friction = 0.8, vertices = {
                { 127.0545, 14.3663 },
                { 126.1535, 20.5000 },
                { 120.4225, 20.5000 },
            } },
            -- fixture 16: right section ground (center-right)
            { friction = 0.8, vertices = {
                { 127.0545, 14.3663 },
                { 120.4225, 20.5000 },
                { 118.7622, 14.3663 },
            } },
            -- fixture 17: right ramp connection
            { friction = 0.8, vertices = {
                { 120.4225, 20.5000 },
                { 119.7939, 20.7387 },
                { 118.7622, 14.3663 },
            } },
            -- fixture 18: right ramp lower triangle
            { friction = 0.8, vertices = {
                { 119.7939, 20.7387 },
                { 117.3067, 20.5000 },
                { 118.7622, 14.3663 },
            } },
            -- fixture 19: center-right ground (large triangle)
            { friction = 0.8, vertices = {
                { 118.7622, 14.3663 },
                { 117.3067, 20.5000 },
                { 103.5368, 20.5000 },
            } },
            -- fixture 20: center-right ground (lower triangle)
            { friction = 0.8, vertices = {
                { 118.7622, 14.3663 },
                { 103.5368, 20.5000 },
                { 101.1005, 14.3663 },
            } },
            -- fixture 21: center ramp connection
            { friction = 0.8, vertices = {
                { 103.5368, 20.5000 },
                { 101.0915, 20.5728 },
                { 101.1005, 14.3663 },
            } },
            -- fixture 22: center left triangle
            { friction = 0.8, vertices = {
                { 101.1005, 14.3663 },
                { 101.0915, 20.5728 },
                { 98.8455, 20.5000 },
            } },
            -- fixture 23: center ground (lower)
            { friction = 0.8, vertices = {
                { 101.1005, 14.3663 },
                { 98.8455, 20.5000 },
                { 86.1386, 14.3650 },
            } },
            -- fixture 24: center ground (flat)
            { friction = 0.8, vertices = {
                { 98.8455, 20.5000 },
                { 86.1386, 20.4987 },
                { 86.1386, 14.3650 },
            } },
        },
    },
}
